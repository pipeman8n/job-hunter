-- =============================================================================
-- Job Hunter V10 → V11: Fit Explicável + Liveness + Legitimidade + Archetype
-- Data: 2026-08-14
-- Inspirado em: santifer/career-ops (A-G eval, ghost-job, archetypes) e
--               MadsLorentzen/ai-job-search (5 dimensões ponderadas).
-- =============================================================================
-- RESUMO:
--   1. job_matches   += tech_score, exp_score, cultura_score, alinhamento_score,
--                       verdict, archetype  → fit_score vira média ponderada
--   2. job_enrichments += is_live, legitimidade, archetype → gate + ghost-job
--   3. vw_jobs_full   → expõe os novos campos (preserva join atual)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. job_matches — Fit Explicável (4 dimensões + veredito + arquétipo)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.job_matches
    ADD COLUMN IF NOT EXISTS tech_score         INTEGER,      -- 0-100
    ADD COLUMN IF NOT EXISTS exp_score          INTEGER,      -- 0-100
    ADD COLUMN IF NOT EXISTS cultura_score      INTEGER,      -- 0-100
    ADD COLUMN IF NOT EXISTS alinhamento_score  INTEGER,      -- 0-100
    ADD COLUMN IF NOT EXISTS verdict            TEXT,         -- Strong|Good|Moderate|Weak|Poor Fit
    ADD COLUMN IF NOT EXISTS archetype          TEXT;         -- Agentic / Automação | LLMOps / IA | ...

CREATE INDEX IF NOT EXISTS idx_matches_archetype  ON public.job_matches(archetype);
CREATE INDEX IF NOT EXISTS idx_matches_verdict    ON public.job_matches(verdict);
CREATE INDEX IF NOT EXISTS idx_matches_tech_score ON public.job_matches(tech_score DESC);

COMMENT ON COLUMN public.job_matches.tech_score        IS '0-100: match de habilidades técnicas (peso 30%)';
COMMENT ON COLUMN public.job_matches.exp_score         IS '0-100: match de experiência no domínio (peso 25%)';
COMMENT ON COLUMN public.job_matches.cultura_score     IS '0-100: fit cultural/comportamental (peso 15%)';
COMMENT ON COLUMN public.job_matches.alinhamento_score IS '0-100: alinhamento com meta de carreira (peso 30%)';
COMMENT ON COLUMN public.job_matches.verdict           IS 'Veredito em faixa: Strong/Good/Moderate/Weak/Poor Fit';
COMMENT ON COLUMN public.job_matches.archetype         IS 'Arquétipo da vaga (career-ops): Agentic/Automação, LLMOps/IA, etc.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. job_enrichments — Liveness gate + Legitimidade (ghost job) + Archetype
-- ─────────────────────────────────────────────────────────────────────────────
-- NOTA: last_verified_at já existe em job_enrichments e é reutilizado como
--       timestamp do liveness check.
ALTER TABLE public.job_enrichments
    ADD COLUMN IF NOT EXISTS is_live      BOOLEAN,     -- NULL=não verificado, TRUE=vivo, FALSE=morto
    ADD COLUMN IF NOT EXISTS legitimidade TEXT,        -- High | Caution | Suspicious
    ADD COLUMN IF NOT EXISTS archetype    TEXT;        -- fallback rule-based (enrich_local)

CREATE INDEX IF NOT EXISTS idx_enrichments_is_live      ON public.job_enrichments(is_live);
CREATE INDEX IF NOT EXISTS idx_enrichments_legitimidade ON public.job_enrichments(legitimidade);
CREATE INDEX IF NOT EXISTS idx_enrichments_archetype    ON public.job_enrichments(archetype);

COMMENT ON COLUMN public.job_enrichments.is_live      IS 'Liveness gate: link da vaga ainda responde? NULL = ainda não verificado';
COMMENT ON COLUMN public.job_enrichments.legitimidade IS 'Ghost-job detection: High (confiável) | Caution | Suspicious';
COMMENT ON COLUMN public.job_enrichments.archetype    IS 'Arquétipo detectado por regra (enrich_local.py), usado como fallback';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. vw_jobs_full — expõe os novos campos
--    (preserva EXATAMENTE o join atual: Indeed direto, demais por URL sem query)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vw_jobs_full AS
SELECT js.url,
    js.id_vaga,
    js.external_id,
    js.status,
    js.notes,
    COALESCE(jm.job_title, 'Sem titulo'::text) AS title,
    COALESCE(jm.job_company, ''::text) AS company,
    jm.fit_score AS score,
    je.location,
    je.salary,
    je.salary_min,
    je.salary_max,
    je.work_model,
    je.seniority,
    je.requirements,
    je.stack,
    je.summary,
    jm.fit_score >= 40 AS ai_match,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM job_blacklist jb
              WHERE jb.is_active = true AND jb.url = js.url)) THEN true
            ELSE false
        END AS is_blocked,
        CASE
            WHEN js.url ~~* '%linkedin%'::text THEN 'LinkedIn'::text
            WHEN js.url ~~* '%infojobs%'::text THEN 'InfoJobs'::text
            WHEN js.url ~~* '%catho%'::text THEN 'Catho'::text
            WHEN js.url ~~* '%indeed%'::text THEN 'Indeed'::text
            ELSE 'Outros'::text
        END AS source,
    jm.scored_at AS searched_at,
    -- Novos campos (apenas colunas novas no final — regra do CREATE OR REPLACE VIEW)
    jm.tech_score,
    jm.exp_score,
    jm.cultura_score,
    jm.alinhamento_score,
    jm.verdict,
    COALESCE(jm.archetype, je.archetype) AS archetype,
    je.is_live,
    je.legitimidade
   FROM job_status js
     LEFT JOIN job_matches jm ON
        CASE
            WHEN js.url ~~* '%indeed%'::text THEN jm.url = js.url
            ELSE regexp_replace(jm.url, '[?&].*$'::text, ''::text, 'g'::text) = regexp_replace(js.url, '[?&].*$'::text, ''::text, 'g'::text)
        END
     LEFT JOIN job_enrichments je ON je.url = js.url;
