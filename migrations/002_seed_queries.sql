-- =============================================================================
-- SEED: Popular job_search_queries com as queries existentes do job_search.py
-- Execute após rodar a migração 001_new_tables.sql
-- =============================================================================

INSERT INTO public.job_search_queries (query_text, label, category, weight, priority, max_results, days_back) VALUES

-- ═══ PRIORIDADE MÁXIMA ═══
(
    'site:br.linkedin.com/jobs ("analista de processos" OR "analista de automacao" OR "consultor BPM" OR "especialista em automacao" OR "product owner" OR "gerente de processos" OR "consultor de processos" OR "transformacao digital") (n8n OR pipefy OR "low code" OR "low-code" OR "BPM" OR "automacao de processos") Sao Paulo SP Brasil 2026',
    '🔥 VIP — BPM/Automação (LinkedIn)',
    'VIP',
    1.5, 1, 5, 7
),

-- Pipefy & Automação
(
    'Pipefy vaga OR job OR hiring "process automation" OR "automação de processos" OR "analista de automação" OR "BPM analyst" analyst OR specialist OR consultant senior remoto Brasil 2026',
    'Pipefy & Automação',
    'Automação',
    1.3, 2, 3, 7
),

-- n8n & Workflow
(
    '"n8n" OR "low-code automation" OR "workflow automation" "process automation" specialist OR analyst OR developer senior remoto Brasil vaga 2026',
    'n8n & Workflow',
    'Automação',
    1.2, 3, 3, 7
),

-- Especialista Low-Code
(
    '"Especialista de Automação Low-Code" OR "Low-Code Automation Specialist" OR "automação low-code" n8n OR pipefy OR make OR zapier senior São Paulo remoto 2026',
    'Low-Code & Automação',
    'Automação',
    1.3, 4, 3, 7
),

-- InfoJobs
(
    'site:infojobs.com.br analista OR especialista OR consultor processos OR automação OR BPM OR "product owner" senior São Paulo remoto 2026',
    'InfoJobs',
    'Portais',
    1.2, 5, 3, 7
),

-- APInfo
(
    'site:apinfo.com analista OR especialista OR consultor processos OR automação OR BPM OR agile senior São Paulo 2026',
    'APInfo',
    'Portais',
    1.1, 6, 3, 7
),

-- BPM & Process Automation
(
    '"Analista de Processos" OR "Senior Process Analyst" BPM BPMN BPMS "automação de processos" Pipefy n8n vagas senior remoto São Paulo 2026',
    'BPM & Automação',
    'BPM',
    1.3, 7, 3, 7
),

-- Digital Transformation
(
    '"Digital Transformation Leader" OR "Transformação Digital" OR "Especialista em Automação" "Gerente de Processos" vagas senior São Paulo remoto 2026',
    'Transformação Digital',
    'Transformação Digital',
    1.2, 8, 3, 7
),

-- Product Owner & Agile
(
    'product owner scrum master agile CSPO vagas senior remoto Brasil 2026',
    'Product Owner & Agile',
    'Agile',
    1.0, 9, 3, 7
),

-- IA & Automation
(
    'inteligência artificial automação IA agentes chatbots vagas senior remoto Brasil 2026',
    'IA & Automação',
    'IA',
    1.1, 10, 3, 7
),

-- Financial Services
(
    'financial services insurance banking process analyst digital transformation vagas senior 2026',
    'Setor Financeiro & Seguros',
    'Setorial',
    1.0, 11, 3, 7
),

-- Consultoria & TI
(
    '"Consultor Sênior BPM" OR "Consultor de Processos" "automação de processos com Pipefy" vagas TI digital São Paulo remoto 2026',
    'Consultoria & TI',
    'Consultoria',
    1.0, 12, 3, 7
),

-- Indeed
(
    '"Indeed" OR "br.indeed" analista processos OR automação OR pipefy OR n8n OR "product owner" senior remoto 2026',
    'Indeed',
    'Portais',
    1.2, 13, 3, 7
),

-- Mercado Livre & Varejo
(
    '"Mercado Livre" OR "Mercado Libre" vagas "product" OR "processos" OR "automation" OR "automação" OR "agile" OR "digital" senior specialist São Paulo Brasil 2026',
    'Mercado Livre & Varejo',
    'Setorial',
    0.9, 14, 3, 7
),

-- Bancos & Fintechs
(
    'site:br.linkedin.com/jobs Santander OR Itaú OR Nubank OR Bradesco "product owner" OR "scrum master" OR processos OR transformação digital senior SP 2026',
    'Bancos & Fintechs',
    'Setorial',
    1.0, 15, 3, 7
);

-- Verificar inserção
SELECT count(*) AS queries_inserted FROM public.job_search_queries;
