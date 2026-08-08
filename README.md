# 🎯 Job Hunter — Pipeline Preditivo de Vagas com IA & Web Scraping

![Python](https://img.shields.io/badge/Python-3.12-blue?logo=python)
![React](https://img.shields.io/badge/React-18-61DAFB?logo=react)
![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?logo=supabase)
![Docker](https://img.shields.io/badge/Docker-Nginx-2496ED?logo=docker)
![DeepSeek](https://img.shields.io/badge/AI-DeepSeek_V4-purple)
![MIT](https://img.shields.io/badge/License-MIT-green)

Plataforma end-to-end automatizada para busca, filtragem inteligente, enriquecimento via LLM e visualização em tempo real de vagas de emprego qualificadas nos segmentos de **BPM, Automação de Processos, Low-Code e IA**.

🔗 **Live Demo:** [vagas.holofoti.com](https://vagas.holofoti.com)

---

## 📐 Arquitetura do Sistema

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   SCRAPER    │ ──▶ │  SUPABASE    │ ──▶ │  DASHBOARD   │ ──▶ │   USUÁRIO    │
│ (Camoufox/   │     │ (PostgreSQL) │     │ (React 18 /   │     │  (Browser)   │
│  Crawl4AI)   │     │              │     │ Glassmorphism)│     │              │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       ▲                                                              │
       │                    ┌──────────────┐                          │
       └────────────────────│ CRON JOBS    │◀─────────────────────────┘
                            │ (Auto-Fix AI)│  (Bloqueios → Filtros)
                            └──────────────┘
```

---

## ✨ Principais Diferenciais Técnicos

### 1. Scraping Anti-Detecção de Alta Performance
- **Camoufox & Playwright:** Bypass de sistemas anti-bot com fingerprint rotativo de browser.
- **Fontes Agregadas:** LinkedIn (Google Guest API), Indeed, Catho e InfoJobs.
- **ID padronizado:** `JH-{FONTE}-{ID_NATIVO}` para rastreabilidade e dedup entre execuções.

### 2. Enriquecimento e Scoring com IA (LLM)
- Uso de **DeepSeek V4 Pro** para calcular o `fit_score` (0 a 100%) da vaga com base no perfil do candidato.
- Extração automática de requisitos, modelo de trabalho (Remoto/Híbrido) e faixa salarial.

### 3. Loop de Feedback Contínuo (Auto-Fix Blacklist)
- **Mecanismo de Aprendizado:** Quando o usuário clica em "Bloquear" no Dashboard, um Cron Job extrai keywords do feedback e atualiza dinamicamente os filtros do Scraper e do Frontend.
- Pipeline incremental: cada execução adiciona vagas sem mexer nas anteriores.

### 4. Dashboard Ultra-Lightweight
- Desenvolvido em **React 18 Standalone + Tailwind/CSS Glassmorphism** sem necessidade de build.
- Conexão em tempo real via Supabase JS SDK.

### 5. Esteira de Deploy Atômica com Zero Downtime
- Script em Shell com builds físicos (`/releases/vX.Y.Z`), versionamento por **Tags Git** e troca instantânea de tráfego via **Symlinks em Nginx**.
- Script de **Rollback automático** em caso de falha.

---

## 🛠️ Tech Stack

- **Linguagens:** Python 3.12, JavaScript (ES6+), SQL, Bash Scripting
- **Scraping & Automação:** Camoufox, Crawl4AI, Playwright, Asyncio
- **Frontend:** React 18, HTML5/CSS3 (Glassmorphism Dark Theme)
- **Banco de Dados:** Supabase (PostgreSQL 15 com Views e Triggers)
- **Infraestrutura & DevOps:** Hetzner Cloud, Docker, Nginx, Hermes Agent, Git/GitHub
- **Inteligência Artificial:** DeepSeek V4 API

---

## 🚀 Como Rodar Localmente

### Pré-requisitos:
- Python 3.12+
- Docker & Docker Compose

### Passos:
1. Clone o repositório:
   ```bash
   git clone https://github.com/ueberson/job-hunter.git
   cd job-hunter
   ```

2. Configure as variáveis de ambiente:
   ```bash
   cp .env.example .env
   # Edite o arquivo .env com suas chaves do Supabase e DeepSeek
   ```

3. Execute o Scraper:
   ```bash
   cd scraper
   pip install -r requirements.txt
   python3 scraper_br.py --max 5 --camoufox --save
   ```

4. Suba o Dashboard:
   ```bash
   docker-compose up -d
   ```
   Acesse em `http://localhost:8080`.

---

## 📄 Licença

Este projeto está sob a licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.
