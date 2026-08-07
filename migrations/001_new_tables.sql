-- =============================================================================
-- Job Hunter V8 → V9: Novas Tabelas Supabase (Cache, Métricas, Auditoria, Versionamento)
-- Data: 2026-07-31
-- Schema: public
-- =============================================================================
-- 
-- RESUMO DAS NOVAS TABELAS (9 tabelas):
-- 1. job_enrichments      → Cache persistente dos dados extraídos pelo smart_enricher.py
-- 2. job_matches          → Scores AI (fit_score, strengths, gaps) do match_scorer.py
-- 3. job_search_runs      → Histórico de execuções de busca (auditoria de pipeline)
-- 4. job_page_cache       → Cache de HTML bruto das páginas de vaga (evita re-fetch)
-- 5. job_notes_history    → Versionamento de notas do usuário (audit trail)
-- 6. job_status_audit     → Log de todas as mudanças de status pelo usuário
-- 7. job_salary_benchmarks → Métricas agregadas de salário por categoria/senioridade
-- 8. job_blacklist        → Blocklist permanente de URLs (substitui expirada_blocklist.json)
-- 9. job_search_queries   → Lookup de queries de busca (substitui JOB_QUERIES inline)
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. job_enrichments — Cache persistente de dados extraídos
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: O smart_enricher.py faz fetch da página, chama DeepSeek para
-- extrair salary, work_model, seniority, stack, requirements, etc. e salva
-- apenas em /tmp/jobs_enriched.json — dados DESCARTADOS entre execuções.
-- Com esta tabela, ao reprocessar a mesma vaga economiza-se ~3-5s de fetch +
-- 1 chamada DeepSeek (~800 tokens). ROI: ~$0.02/vaga reenriquecida.
--
-- IMPACTO NO FRONTEND: O dashboard pode carregar `job_enrichments` diretamente
-- em vez de depender do JSON estático. Permite paginação server-side.

CREATE TABLE IF NOT EXISTS public.job_enrichments (
    id              BIGSERIAL PRIMARY KEY,
    url             TEXT NOT NULL,
    -- Campos extraídos pelo smart_enricher.py
    salary          TEXT,                          -- "R$ 12.000 a R$ 15.000"
    salary_min      INTEGER,                      -- 12000
    salary_max      INTEGER,                      -- 15000
    work_model      TEXT,                          -- remoto | presencial | hibrido
    seniority       TEXT,                          -- junior | pleno | senior | especialista
    contract_type   TEXT,                          -- CLT | PJ | both
    requirements    JSONB DEFAULT '[]'::jsonb,    -- ["Experiência em BPM", "Inglês avançado"]
    benefits        JSONB DEFAULT '[]'::jsonb,    -- ["Plano de Saúde", "Vale Refeição"]
    stack           JSONB DEFAULT '[]'::jsonb,    -- ["n8n", "Pipefy", "Python"]
    summary         TEXT,                          -- Resumo da vaga em português (1 frase)
    -- Metadados de extração
    source_url      TEXT,                          -- URL original da página fetchada
    fetch_status    TEXT DEFAULT 'success',        -- success | fetch_error | skipped | parse_error
    fetch_error     TEXT,                          -- Mensagem de erro se fetch falhou
    ai_model        TEXT DEFAULT 'deepseek-chat',  -- Modelo usado na extração
    ai_tokens_used  INTEGER DEFAULT 0,            -- Tokens consumidos (cost tracking)
    enriched_at     TIMESTAMPTZ DEFAULT NOW(),    -- Quando foi enriquecido
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT uq_job_enrichments_url UNIQUE (url)
);

-- Índices para consultas do dashboard:
-- - Filtrar por work_model (Remoto/Híbrido/Presencial)
-- - Filtrar por seniority (Júnior/Pleno/Sênior/Especialista)
-- - Ordenar por salary_min (maior salário primeiro)
CREATE INDEX IF NOT EXISTS idx_enrichments_work_model ON public.job_enrichments(work_model);
CREATE INDEX IF NOT EXISTS idx_enrichments_seniority ON public.job_enrichments(seniority);
CREATE INDEX IF NOT EXISTS idx_enrichments_salary_min ON public.job_enrichments(salary_min DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_enrichments_fetch_status ON public.job_enrichments(fetch_status);
CREATE INDEX IF NOT EXISTS idx_enrichments_enriched_at ON public.job_enrichments(enriched_at DESC);

COMMENT ON TABLE public.job_enrichments IS 'Cache persistente de dados extraídos pelo smart_enricher.py via DeepSeek. Evita re-fetch e re-enriquecimento da mesma vaga.';
COMMENT ON COLUMN public.job_enrichments.ai_tokens_used IS 'Para cost tracking do pipeline de enriquecimento';


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. job_matches — Scores AI do match_scorer.py
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: O match_scorer.py chama DeepSeek para avaliar fit entre CV
-- e vaga, gerando fit_score, strengths, gaps, recommendation, match_level.
-- Resultados são salvos em /tmp/jobs_scored.json e PERDIDOS. Com esta tabela:
-- - Scores persistem entre execuções (não precisa re-scorear mesma vaga)
-- - Histórico de evolução de match (mesma vaga pode ser reavaliada)
-- - Análise: quais skills mais aparecem em gaps? Quais vagas têm melhor fit?
-- - ROI: ~$0.03/vaga re-scoreada (600 tokens DeepSeek)
--
-- IMPACTO: O dashboard pode ordenar por fit_score direto do Supabase,
-- eliminando a dependência do JSON estático.

CREATE TABLE IF NOT EXISTS public.job_matches (
    id              BIGSERIAL PRIMARY KEY,
    url             TEXT NOT NULL,
    -- Scores do DeepSeek
    fit_score       INTEGER NOT NULL DEFAULT 0,   -- 0-100
    match_level     TEXT,                          -- Perfect Match | Strong Match | Good Match | Partial Match | Weak Match
    strengths       JSONB DEFAULT '[]'::jsonb,    -- ["14 anos em BPM", "Experiência com n8n", ...]
    gaps            JSONB DEFAULT '[]'::jsonb,    -- ["Falta experiência com SAP", ...]
    recommendation  TEXT,                          -- Frase em português com veredito
    -- Metadados
    ai_model        TEXT DEFAULT 'deepseek-chat',
    ai_tokens_used  INTEGER DEFAULT 0,
    cv_hash         TEXT,                          -- Hash do CV usado (detecta mudanças no CV)
    pre_filtered    BOOLEAN DEFAULT FALSE,         -- TRUE se foi rejeitado por quick_reject (regras)
    job_title       TEXT,                          -- Título da vaga no momento do match
    job_company     TEXT,                          -- Empresa no momento do match
    scored_at       TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT uq_job_matches_url_scored UNIQUE (url, scored_at)
);

-- Índices para queries do dashboard:
-- - Top vagas por fit_score (ordenação principal)
-- - Filtrar por match_level
-- - Agrupar gaps/strenghs para analytics
CREATE INDEX IF NOT EXISTS idx_matches_fit_score ON public.job_matches(fit_score DESC);
CREATE INDEX IF NOT EXISTS idx_matches_match_level ON public.job_matches(match_level);
CREATE INDEX IF NOT EXISTS idx_matches_scored_at ON public.job_matches(scored_at DESC);
CREATE INDEX IF NOT EXISTS idx_matches_url ON public.job_matches(url);

COMMENT ON TABLE public.job_matches IS 'Scores AI do match_scorer.py: fit_score, strengths, gaps, recommendation. Permite histórico de reavaliações.';
COMMENT ON COLUMN public.job_matches.cv_hash IS 'MD5 do CV usado. Detecta quando o CV foi atualizado e scores antigos precisam ser reavaliados.';


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. job_search_runs — Histórico de execuções do pipeline
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: O job_search.py roda via n8n/cron mas não registra nada.
-- Sem métricas, é impossível saber:
-- - Quantas vagas foram encontradas em cada execução?
-- - Qual query trouxe mais resultados?
-- - Quanto custou em tokens cada run?
-- - O pipeline está ficando mais lento?
-- - Houve erro em alguma etapa?
--
-- IMPACTO: Dashboard de monitoramento do pipeline + alertas de falha.

CREATE TABLE IF NOT EXISTS public.job_search_runs (
    id              BIGSERIAL PRIMARY KEY,
    run_id          UUID DEFAULT gen_random_uuid(), -- Identificador único da execução
    -- Métricas da etapa de busca
    search_queries  INTEGER DEFAULT 0,              -- Número de queries executadas
    jobs_found      INTEGER DEFAULT 0,              -- Vagas brutas encontradas
    jobs_deduped    INTEGER DEFAULT 0,              -- Após deduplicação
    jobs_blocked    INTEGER DEFAULT 0,              -- Bloqueadas por domínio/qualidade
    -- Métricas da etapa de enriquecimento
    enriched_count  INTEGER DEFAULT 0,              -- Vagas enriquecidas com sucesso
    enrich_errors   INTEGER DEFAULT 0,              -- Falhas de fetch/parse
    enrich_skipped  INTEGER DEFAULT 0,              -- Puladas (pre-filter)
    -- Métricas da etapa de scoring
    scored_count    INTEGER DEFAULT 0,              -- Vagas que passaram pelo AI match
    score_prefiltered INTEGER DEFAULT 0,            -- Rejeitadas por quick_reject
    -- Métricas de custo
    ai_calls        INTEGER DEFAULT 0,              -- Total de chamadas à API DeepSeek
    ai_tokens       INTEGER DEFAULT 0,              -- Tokens totais consumidos
    est_cost_usd    NUMERIC(10,6) DEFAULT 0,        -- Custo estimado em USD
    -- Métricas de resultado
    avg_score       INTEGER,                        -- Score médio das vagas encontradas
    jobs_above_50   INTEGER DEFAULT 0,              -- Vagas com score ≥ 50%
    jobs_above_70   INTEGER DEFAULT 0,              -- Vagas com score ≥ 70%
    remote_count    INTEGER DEFAULT 0,              -- Vagas remotas/híbridas
    sp_count        INTEGER DEFAULT 0,              -- Vagas em São Paulo
    -- Status da execução
    status          TEXT DEFAULT 'running',          -- running | completed | failed | partial
    error_message   TEXT,                            -- Erro se status=failed
    duration_sec    NUMERIC(10,2),                   -- Duração total em segundos
    trigger         TEXT DEFAULT 'cron',             -- cron | manual | api | n8n
    -- Timestamps
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    finished_at     TIMESTAMPTZ,

    CONSTRAINT uq_search_runs_run_id UNIQUE (run_id)
);

CREATE INDEX IF NOT EXISTS idx_search_runs_started_at ON public.job_search_runs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_search_runs_status ON public.job_search_runs(status);

COMMENT ON TABLE public.job_search_runs IS 'Histórico de execuções do pipeline job_search.py → smart_enricher.py → match_scorer.py. Métricas de performance e custo.';


-- ═══════════════════════════════════════════════════════════════════════════
-- 4. job_page_cache — Cache de HTML bruto das páginas de vaga
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: O smart_enricher.py faz urllib.request.urlopen() para cada
-- vaga (até 10 por run). A mesma vaga aparece em execuções sucessivas e o
-- HTML é re-fetchado. Com cache:
-- - Economiza ~2-5s por fetch (10 vagas = 20-50s por run)
-- - Reduz tráfego e evita rate limiting dos sites de vaga
-- - TTL configurável (páginas de vaga raramente mudam em < 24h)
-- - Armazena o texto extraído (10k chars) para evitar re-parsing
--
-- NOTA: Usar BYTEA para HTML bruto ou TEXT para o texto extraído.
-- Como o smart_enricher.py já faz strip de HTML, guardamos o texto limpo.

CREATE TABLE IF NOT EXISTS public.job_page_cache (
    id              BIGSERIAL PRIMARY KEY,
    url             TEXT NOT NULL,
    -- Conteúdo
    raw_text        TEXT,                           -- Texto extraído (até 10k chars, após strip HTML)
    text_hash       TEXT,                           -- MD5 do texto (detecta mudanças na página)
    content_length  INTEGER,                        -- Tamanho do conteúdo original
    -- Metadados do fetch
    fetch_status    TEXT DEFAULT 'success',         -- success | timeout | ssl_error | http_error | blocked
    fetch_error     TEXT,                           -- Detalhes do erro
    fetch_duration_ms INTEGER,                      -- Tempo do fetch em ms
    http_status     INTEGER,                        -- HTTP status code
    -- Controle de cache
    ttl_hours       INTEGER DEFAULT 24,             -- Tempo de vida em horas
    expires_at      TIMESTAMPTZ,                    -- Quando o cache expira
    -- Relacionamento
    enrichment_id   BIGINT,                         -- FK para job_enrichments (se já foi enriquecida)
    -- Timestamps
    fetched_at      TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT uq_job_page_cache_url UNIQUE (url)
);

CREATE INDEX IF NOT EXISTS idx_page_cache_expires ON public.job_page_cache(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_page_cache_fetch_status ON public.job_page_cache(fetch_status);
CREATE INDEX IF NOT EXISTS idx_page_cache_url_hash ON public.job_page_cache(url, text_hash);

COMMENT ON TABLE public.job_page_cache IS 'Cache de HTML/texto de páginas de vaga. Evita re-fetch das mesmas URLs entre execuções do pipeline. TTL padrão 24h.';


-- ═══════════════════════════════════════════════════════════════════════════
-- 5. job_notes_history — Versionamento de notas do usuário
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: O job_status.notes é sobrescrito em toda alteração.
-- Se o usuário escreveu "RH ligou dia 15/07, retornar dia 18/07" e depois
-- mudou para "Entrevista marcada 20/07", a nota anterior é PERDIDA.
-- Com versionamento:
-- - Histórico completo de alterações nas notas
-- - Diff entre versões (o que mudou?)
-- - Quem alterou? Quando?
-- - Rollback para versão anterior
--
-- IMPACTO: Auditoria completa do pipeline de candidatura.

CREATE TABLE IF NOT EXISTS public.job_notes_history (
    id              BIGSERIAL PRIMARY KEY,
    job_url         TEXT NOT NULL,
    -- Versão da nota
    version         INTEGER NOT NULL DEFAULT 1,
    note_text       TEXT,                           -- Conteúdo da nota nesta versão
    note_length     INTEGER,                        -- Tamanho em caracteres
    -- Metadata da alteração
    changed_by      TEXT DEFAULT 'user',            -- user | system | ai | n8n
    change_type     TEXT DEFAULT 'update',          -- create | update | delete
    previous_hash   TEXT,                           -- Hash da versão anterior (chain de integridade)
    -- Timestamps
    changed_at      TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT uq_job_notes_version UNIQUE (job_url, version)
);

CREATE INDEX IF NOT EXISTS idx_notes_history_url ON public.job_notes_history(job_url, version DESC);
CREATE INDEX IF NOT EXISTS idx_notes_history_changed_at ON public.job_notes_history(changed_at DESC);

COMMENT ON TABLE public.job_notes_history IS 'Versionamento completo de notas por vaga. Cada alteração gera nova versão. Permite auditoria e rollback.';
COMMENT ON COLUMN public.job_notes_history.previous_hash IS 'SHA256 da versão anterior para cadeia de integridade (tamper-evident).';


-- ═══════════════════════════════════════════════════════════════════════════
-- 6. job_status_audit — Log de auditoria de mudanças de status
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: O job_status só armazena o status ATUAL. Não há registro de:
-- - Quando a vaga foi favoritada? Descartada? Reaberta?
-- - Quanto tempo ficou em cada status? (métricas de funil)
-- - Quantas vezes o status mudou? (indecisão do usuário)
-- - Padrões: vagas descartadas rapidamente vs. vagas que ficam semanas em "favorita"
--
-- IMPACTO: Métricas de funil de recrutamento + auditoria de ações do usuário.

CREATE TABLE IF NOT EXISTS public.job_status_audit (
    id              BIGSERIAL PRIMARY KEY,
    job_url         TEXT NOT NULL,
    -- Status
    old_status      TEXT,                           -- Status anterior (NULL na primeira ação)
    new_status      TEXT NOT NULL,                  -- Novo status
    -- Estados possíveis: pending | favorita | enviada | entrevista | descartada | expirada
    -- Metadados
    source          TEXT DEFAULT 'dashboard',       -- dashboard | api | n8n | telegram
    user_agent      TEXT,                           -- Browser/device info (opcional)
    notes_snapshot  TEXT,                           -- Snapshot das notas no momento da mudança
    -- Timestamps
    changed_at      TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_status_audit_url ON public.job_status_audit(job_url, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_status_audit_new_status ON public.job_status_audit(new_status);
CREATE INDEX IF NOT EXISTS idx_status_audit_changed_at ON public.job_status_audit(changed_at DESC);
-- Índice composto para métricas de funil: "quantas vagas foram de favorita→entrevista este mês?"
CREATE INDEX IF NOT EXISTS idx_status_audit_transition ON public.job_status_audit(old_status, new_status);

COMMENT ON TABLE public.job_status_audit IS 'Log imutável de todas as transições de status. Permite métricas de funil e auditoria completa.';


-- ═══════════════════════════════════════════════════════════════════════════
-- 7. job_salary_benchmarks — Métricas agregadas de salário
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: O dashboard mostra "Salário Médio" e "Senioridade Top" nos
-- KPIs. Atualmente, se não há dados na execução atual, mostra "N/D".
-- Com métricas históricas agregadas, pode-se mostrar:
-- - Salário médio das ÚLTIMAS 4 SEMANAS (mais representativo)
-- - Tendência: salários estão subindo ou descendo?
-- - Benchmark: média de mercado vs. média das vagas encontradas
-- - Por categoria: "Média BPM/Automação: R$ 14k" vs "Média Agile: R$ 11k"
--
-- IMPACTO: KPIs do dashboard ficam mais informativos e menos dependentes
-- de ter vagas com salário na execução atual.

CREATE TABLE IF NOT EXISTS public.job_salary_benchmarks (
    id              BIGSERIAL PRIMARY KEY,
    -- Dimensões
    category        TEXT,                           -- query_label (ex: "BPM & Automação", "Product Owner & Agile")
    seniority       TEXT,                           -- junior | pleno | senior | especialista
    work_model      TEXT,                           -- remoto | presencial | hibrido
    contract_type   TEXT,                           -- CLT | PJ | both
    -- Métricas da janela
    window_start    DATE NOT NULL,                  -- Início da janela de agregação
    window_end      DATE NOT NULL,                  -- Fim da janela
    sample_size     INTEGER DEFAULT 0,              -- Quantas vagas na amostra
    -- Estatísticas
    salary_min_avg  NUMERIC(12,2),                  -- Média do salary_min
    salary_max_avg  NUMERIC(12,2),                  -- Média do salary_max
    salary_min_p25  NUMERIC(12,2),                  -- Percentil 25
    salary_min_p50  NUMERIC(12,2),                  -- Mediana (p50)
    salary_min_p75  NUMERIC(12,2),                  -- Percentil 75
    -- Metadados
    computed_at     TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT uq_salary_benchmark UNIQUE (category, seniority, work_model, contract_type, window_start, window_end)
);

CREATE INDEX IF NOT EXISTS idx_salary_bench_category ON public.job_salary_benchmarks(category);
CREATE INDEX IF NOT EXISTS idx_salary_bench_seniority ON public.job_salary_benchmarks(seniority);
CREATE INDEX IF NOT EXISTS idx_salary_bench_window ON public.job_salary_benchmarks(window_end DESC);

COMMENT ON TABLE public.job_salary_benchmarks IS 'Métricas agregadas de salário por categoria/senioridade/modelo/tipo de contrato. Alimenta KPIs do dashboard e análises de tendência.';


-- ═══════════════════════════════════════════════════════════════════════════
-- 8. job_blacklist — Blocklist permanente de URLs
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: Atualmente a blocklist é um arquivo JSON local
-- (/root/agent-reach/expirada_blocklist.json). Problemas:
-- - Não sincronizado entre frontend e backend
-- - Perdido se o arquivo for deletado
-- - Sem metadados de quem bloqueou e por quê
-- - Difícil de auditar/desbloquear
--
-- Com esta tabela no Supabase:
-- - Frontend e backend compartilham a mesma blocklist
-- - API pode consultar antes de exibir vagas
-- - Desbloqueio é simples (soft delete)
-- - Métricas: quantas vagas bloqueadas por mês? Motivo mais comum?

CREATE TABLE IF NOT EXISTS public.job_blacklist (
    id              BIGSERIAL PRIMARY KEY,
    url             TEXT NOT NULL,
    -- Motivo
    reason          TEXT DEFAULT 'Marcada como descartada/expirada pelo usuário',
    reason_type     TEXT DEFAULT 'user_action',     -- user_action | domain_block | duplicate | low_quality | expired
    -- Metadados
    blocked_by      TEXT DEFAULT 'user',            -- user | system | auto
    is_active       BOOLEAN DEFAULT TRUE,           -- FALSE = desbloqueado (soft delete)
    unblocked_at    TIMESTAMPTZ,                    -- Quando foi desbloqueado
    -- Timestamps
    blocked_at      TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT uq_job_blacklist_url UNIQUE (url)
);

CREATE INDEX IF NOT EXISTS idx_blacklist_active ON public.job_blacklist(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_blacklist_url ON public.job_blacklist(url);
CREATE INDEX IF NOT EXISTS idx_blacklist_reason_type ON public.job_blacklist(reason_type);

COMMENT ON TABLE public.job_blacklist IS 'Blocklist permanente de URLs. Frontend e backend compartilham via Supabase. Soft-delete para desbloqueio.';


-- ═══════════════════════════════════════════════════════════════════════════
-- 9. job_search_queries — Catálogo de queries de busca
-- ═══════════════════════════════════════════════════════════════════════════
-- JUSTIFICATIVA: As queries de busca estão hardcoded em JOB_QUERIES no
-- job_search.py. Para adicionar/remover/ajustar queries é preciso editar
-- o código e redeploy. Com esta tabela:
-- - Frontend/admin pode gerenciar queries sem tocar no código
-- - Ativar/desativar queries (active flag)
-- - Ajustar peso (weight) por query
-- - Métricas: qual query trouxe mais vagas? qual tem melhor avg_score?
-- - A/B testing de queries (comparar performance)
--
-- IMPACTO: Flexibilidade operacional + métricas de performance por query.

CREATE TABLE IF NOT EXISTS public.job_search_queries (
    id              BIGSERIAL PRIMARY KEY,
    -- Query
    query_text      TEXT NOT NULL,                  -- Texto da query Exa/Firecrawl
    label           TEXT NOT NULL,                  -- Nome amigável ("BPM & Automação", "Product Owner & Agile")
    category        TEXT,                           -- Agrupamento (ex: "VIP", "Automação", "Agile")
    -- Configuração
    weight          NUMERIC(3,2) DEFAULT 1.0,      -- Multiplicador de score (1.0 = normal, 1.5 = VIP)
    priority        INTEGER DEFAULT 0,              -- Ordem de execução (menor = primeiro)
    is_active       BOOLEAN DEFAULT TRUE,           -- FALSE = query pausada
    max_results     INTEGER DEFAULT 3,              -- Resultados por query
    days_back       INTEGER DEFAULT 7,              -- Filtrar vagas dos últimos N dias
    -- Metadados
    created_by      TEXT DEFAULT 'system',
    notes           TEXT,                           -- Contexto/justificativa da query
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_search_queries_active ON public.job_search_queries(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_search_queries_category ON public.job_search_queries(category);
CREATE INDEX IF NOT EXISTS idx_search_queries_priority ON public.job_search_queries(priority);

COMMENT ON TABLE public.job_search_queries IS 'Catálogo de queries de busca gerenciável. Substitui o hardcoded JOB_QUERIES do job_search.py. Permite ativar/desativar e ajustar pesos sem redeploy.';


-- ═══════════════════════════════════════════════════════════════════════════
-- 10. MELHORIA NA TABELA EXISTENTE: job_status
-- ═══════════════════════════════════════════════════════════════════════════
-- A tabela job_status atual tem: url, status, notes, updated_at
-- Sugestão de melhorias (opcional, não quebra compatibilidade):

-- a) Adicionar coluna para tracking de mudanças (já existe trigger?)
-- b) Índice composto para queries do dashboard
-- c) Coluna para soft-delete de notas (evitar perda)

-- Este bloco é opcional — execute apenas se quiser migrar a tabela existente:
/*
ALTER TABLE public.job_status
    ADD COLUMN IF NOT EXISTS id BIGSERIAL,
    ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS notes_version INTEGER DEFAULT 1,
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Índice para busca paginada com filtros:
CREATE INDEX IF NOT EXISTS idx_job_status_composite
    ON public.job_status(status, updated_at DESC);

-- Índice para buscar URLs em lote (melhora .in('url', urls) com 500+ URLs):
CREATE INDEX IF NOT EXISTS idx_job_status_url_btree
    ON public.job_status USING btree(url);
*/


-- ═══════════════════════════════════════════════════════════════════════════
-- TRIGGER: Atualizar updated_at automaticamente
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar trigger nas tabelas que têm updated_at
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN
        SELECT table_name FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'updated_at'
          AND table_name IN ('job_enrichments', 'job_matches', 'job_search_queries', 'job_status')
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS trg_%I_updated_at ON public.%I;
            CREATE TRIGGER trg_%I_updated_at
                BEFORE UPDATE ON public.%I
                FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
        ', t, t, t, t);
    END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════════════
-- TRIGGER: Registrar mudanças de status automaticamente
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.log_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status)
       OR (TG_OP = 'INSERT') THEN
        INSERT INTO public.job_status_audit (
            job_url,
            old_status,
            new_status,
            source,
            notes_snapshot,
            changed_at
        ) VALUES (
            NEW.url,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.status ELSE NULL END,
            NEW.status,
            'supabase_trigger',
            NEW.notes,
            NOW()
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar trigger na tabela job_status (se ainda não existir)
DROP TRIGGER IF EXISTS trg_job_status_audit ON public.job_status;
CREATE TRIGGER trg_job_status_audit
    AFTER INSERT OR UPDATE OF status ON public.job_status
    FOR EACH ROW EXECUTE FUNCTION public.log_status_change();


-- ═══════════════════════════════════════════════════════════════════════════
-- VIEWS ÚTEIS PARA O DASHBOARD
-- ═══════════════════════════════════════════════════════════════════════════

-- View: Vagas completas com enrichment + match + status (JOIN único)
CREATE OR REPLACE VIEW public.vw_jobs_full AS
SELECT
    js.url,
    js.status,
    js.notes,
    js.updated_at AS status_updated_at,
    -- Enrichment
    je.salary,
    je.salary_min,
    je.salary_max,
    je.work_model,
    je.seniority,
    je.contract_type,
    je.requirements,
    je.benefits,
    je.stack,
    je.summary,
    je.enriched_at,
    -- AI Match
    jm.fit_score,
    jm.match_level,
    jm.strengths,
    jm.gaps,
    jm.recommendation,
    jm.scored_at,
    -- Blacklist check
    CASE WHEN jb.id IS NOT NULL THEN TRUE ELSE FALSE END AS is_blacklisted
FROM
    public.job_status js
LEFT JOIN LATERAL (
    SELECT * FROM public.job_enrichments je2
    WHERE je2.url = js.url
    ORDER BY je2.enriched_at DESC
    LIMIT 1
) je ON TRUE
LEFT JOIN LATERAL (
    SELECT * FROM public.job_matches jm2
    WHERE jm2.url = js.url
    ORDER BY jm2.scored_at DESC
    LIMIT 1
) jm ON TRUE
LEFT JOIN public.job_blacklist jb ON jb.url = js.url AND jb.is_active = TRUE;

COMMENT ON VIEW public.vw_jobs_full IS 'Visão completa de vagas: status + enrichment + AI match + blacklist. Use para queries do dashboard.';


-- View: Métricas de funil de recrutamento (últimos 30 dias)
CREATE OR REPLACE VIEW public.vw_funnel_metrics AS
SELECT
    new_status AS stage,
    COUNT(DISTINCT job_url) AS unique_jobs,
    COUNT(*) AS total_transitions,
    MIN(changed_at) AS first_entry,
    MAX(changed_at) AS last_entry
FROM public.job_status_audit
WHERE changed_at >= NOW() - INTERVAL '30 days'
GROUP BY new_status
ORDER BY
    CASE new_status
        WHEN 'favorita' THEN 1
        WHEN 'enviada' THEN 2
        WHEN 'entrevista' THEN 3
        WHEN 'descartada' THEN 4
        WHEN 'expirada' THEN 5
        ELSE 6
    END;

COMMENT ON VIEW public.vw_funnel_metrics IS 'Métricas de funil de recrutamento: vagas por estágio nos últimos 30 dias.';


-- View: Último search run (para dashboard de monitoramento)
CREATE OR REPLACE VIEW public.vw_last_search_run AS
SELECT *
FROM public.job_search_runs
WHERE status = 'completed'
ORDER BY started_at DESC
LIMIT 1;

COMMENT ON VIEW public.vw_last_search_run IS 'Última execução bem-sucedida do pipeline de busca.';


-- ═══════════════════════════════════════════════════════════════════════════
-- RLS POLICIES (Row Level Security) — PRODUÇÃO
-- ═══════════════════════════════════════════════════════════════════════════
-- Ajustar conforme necessidade. Exemplo: permitir leitura anônima, escrita autenticada.

-- Habilitar RLS nas tabelas novas
ALTER TABLE public.job_enrichments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_search_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_page_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_notes_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_status_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_salary_benchmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_blacklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_search_queries ENABLE ROW LEVEL SECURITY;

-- Política: permitir SELECT anônimo (dashboard público)
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN
        SELECT unnest(ARRAY[
            'job_enrichments', 'job_matches', 'job_search_runs',
            'job_page_cache', 'job_salary_benchmarks', 'job_search_queries'
        ])
    LOOP
        EXECUTE format('
            DROP POLICY IF EXISTS "Allow anonymous select" ON public.%I;
            CREATE POLICY "Allow anonymous select" ON public.%I
                FOR SELECT USING (true);
        ', t, t);
    END LOOP;
END $$;

-- Política: permitir INSERT/UPDATE autenticado (para o pipeline)
-- Ajustar auth.uid() conforme seu setup de autenticação Supabase
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN
        SELECT unnest(ARRAY[
            'job_enrichments', 'job_matches', 'job_search_runs',
            'job_page_cache', 'job_salary_benchmarks', 'job_blacklist',
            'job_search_queries', 'job_notes_history', 'job_status_audit'
        ])
    LOOP
        EXECUTE format('
            DROP POLICY IF EXISTS "Allow authenticated insert" ON public.%I;
            CREATE POLICY "Allow authenticated insert" ON public.%I
                FOR INSERT WITH CHECK (true);
        ', t, t);
        EXECUTE format('
            DROP POLICY IF EXISTS "Allow authenticated update" ON public.%I;
            CREATE POLICY "Allow authenticated update" ON public.%I
                FOR UPDATE USING (true) WITH CHECK (true);
        ', t, t);
    END LOOP;
END $$;

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================
-- 
-- PRÓXIMOS PASSOS:
-- 1. Executar este SQL no Supabase SQL Editor
-- 2. Popular job_search_queries com as queries do job_search.py (JOB_QUERIES)
-- 3. Adaptar smart_enricher.py para gravar em job_enrichments + job_page_cache
-- 4. Adaptar match_scorer.py para gravar em job_matches
-- 5. Adaptar job_search.py para gravar em job_search_runs
-- 6. Frontend: mudar fetchJobs() para usar vw_jobs_full via Supabase REST API
-- 7. Frontend: adicionar save a job_status_audit e job_notes_history
-- 8. Criar job de agregação para job_salary_benchmarks (cron semanal)
-- =============================================================================
