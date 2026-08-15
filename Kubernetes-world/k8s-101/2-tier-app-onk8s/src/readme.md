# LivingDevOps Portal

A Flask bootcamp app that combines a **student portal**, **sprint retrospectives**, **Jira-style ticketing**, and **team management** — containerized for AWS ECS (Day 9).

**Location:** `April26-bootcamp/day9-ecs-terraform/src`

---

## Quick start

### Docker (recommended)

```bash
cd day9-ecs-terraform/src
docker compose up --build
```

| URL | Purpose |
|-----|---------|
| http://localhost:8000 | App |
| http://localhost:8000/health | Health check |
| http://localhost:8000/metrics | Prometheus metrics |

### Local dev (without Docker)

```bash
cd day9-ecs-terraform/src
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export DB_LINK="sqlite:////tmp/student_portal.db"
gunicorn --bind 0.0.0.0:8000 run:app
```

### Run tests

```bash
source .venv/bin/activate
pytest          # 21 tests — auth, portal, retros, teams, tickets
pytest -v       # verbose output
```

**Test coverage (21 tests, all passing):**

| Area | What is tested |
|------|----------------|
| Health | `/health` returns connected DB |
| Auth | Register, login, invalid credentials |
| Admin seed | Admins created from `data/admins.json` |
| Student portal | Students, attendance, assignments |
| Retros | Admin create, cards/likes/comments, guest join |
| Teams | Create team, add member, bulk CSV import |
| Tickets | Seeded issues, create/assign/subtasks/comments, team scoping |
| Access control | Non-admins cannot create retros; tickets scoped to your teams |

---

## What the app does

```text
┌─────────────────────────────────────────────────────────────┐
│                  LivingDevOps Portal                        │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   Portal     │    Retros    │    Teams     │    Tickets     │
│  (Dashboard, │  Sticky-note │  Squads +    │  Jira-style    │
│   Students,  │  sprint      │  members +   │  issues,       │
│   Classes…)  │  boards      │  bulk import │  subtasks      │
└──────────────┴──────────────┴──────────────┴────────────────┘
```

On every startup the app:

1. Creates database tables (`db.create_all()`)
2. Applies lightweight schema migrations (`ensure_schema()`)
3. Seeds admin users from `data/admins.json`
4. Seeds a default **Platform DevOps** team from `data/devops_teams.json`
5. Seeds 5 retro boards from `data/devops_retros.json`
6. Seeds 6 sample tickets from `data/devops_tickets.json`

---

## User roles

| Role | How you get it | What you can do |
|------|----------------|-----------------|
| **Admin** | Seeded on startup (`data/admins.json`) | Create/close retro boards; everything else a normal user can do |
| **Registered user** | `/register` | Full portal, teams, tickets, join retros |
| **Guest** | Join retro via share link | Retros only — no portal, teams, or tickets |

### Default admin accounts

Defined in `data/admins.json`, created automatically on startup:

| Username | Email | Default password | Env override |
|----------|-------|------------------|--------------|
| `livingdevops` | livingdevops@gmail.com | `LivingDevops1!` | `ADMIN_PASSWORD` |
| `devopscaptain` | devopscaptain@bootcamp.local | `ShipIt2026!` | `DEVOPS_CAPTAIN_PASSWORD` |

Password env vars override the JSON defaults when set (e.g. in `docker-compose.yaml`).

---

## Authentication

| Route | Description |
|-------|-------------|
| `/register` | Create account (username, email, password) |
| `/login` | Sign in |
| `/logout` | Sign out |

**Password rules:** minimum 8 characters, at least one uppercase, one lowercase, and one number.

After registering you land on the **Dashboard**. Guests who sign up from a retro link are redirected back to that retro.

---

## Student portal

Available from the nav under **More** (full accounts only).

| Route | Feature |
|-------|---------|
| `/` | Dashboard — student stats, announcements, upcoming assignments |
| `/students` | Add, edit, delete students |
| `/attendance` | Mark daily attendance (Present / Absent) |
| `/classes` | Class sessions with links to recordings, code, resources |
| `/assignments` | Homework with due dates and completion toggle |
| `/announcements` | Pinned and regular announcements |

---

## DevOps Retros (`/retro`)

Sprint retrospective boards with sticky notes.

### Seeded boards (visible to all logged-in users)

Loaded from `data/devops_retros.json`:

- ECS Day 9 — Terraform Ship Retro
- Kubernetes Pod Crash Bingo
- CI/CD Green Button Envy
- Docker Image Size Intervention
- Incident Post-Mortem: Who Pushed to Prod?

Each board includes starter sticky notes in three columns.

### How retros work

1. **Admins** create boards at `/retro/create`
2. Each board gets a **share link** — copy and send to the team
3. Join page (`/retro/join/<token>`):
   - **Guest join** — display name only, no account
   - **Login / Register** — full account, redirected back to the board
4. Three columns: **What Went Well** · **What Needs Improvement** · **Action Items**
5. Like cards and add comments
6. Admin can **close** a retro when done

**Regular users** can open any existing retro board and add notes. They cannot create new boards (admin only).

---

## Teams (`/teams`)

Squads for organizing ticket work. Each team has a **project key** used in ticket IDs (like Jira).

### Create a team

1. Go to **Teams → Create Team**
2. Set name, project key (2–10 letters/numbers, e.g. `SRE`), and description
3. You become the **owner**

Ticket keys use your project key: `SRE-1`, `SRE-2`, …

### Add members

**Single member** (team owners only):

- Open team → **Add Member**
- Enter email and password
- If the email is new, an account is created automatically
- If the user already exists, they are added to the team (password not required)

**Bulk import** (CSV file or paste):

```csv
email,password,username
sre1@bootcamp.local,SrePass1!,sre1
sre2@bootcamp.local,SrePass2!,sre2
```

- Header row optional
- Username optional (derived from email if omitted)
- Password required for new accounts (same rules as registration)

### Seeded team

`data/devops_teams.json` creates **Platform DevOps** (`DEV` key) with admins as members. Seeded tickets (`DEV-1` … `DEV-6`) belong to this team and are only visible to its members.

---

## Tickets (`/tickets`)

Jira-style issue tracking scoped to teams.

### Ticket fields

| Field | Options |
|-------|---------|
| **Key** | `{PROJECT_KEY}-{number}` e.g. `DEV-1`, `MY-1` |
| **Type** | Bug, Task, Story, Epic |
| **Status** | Backlog → To Do → In Progress → In Review → Done |
| **Priority** | Lowest → Highest |
| **Assignee** | Must be a member of the ticket's team |
| **Reporter** | User who created the ticket |

### Subtasks & comments

- Break tickets into **subtasks** with their own status and assignee
- Toggle subtasks done/undone
- **Comments** on the ticket and on individual subtasks

### Access rules

- You must belong to a **team** before creating tickets
- You only see tickets for **teams you are on**
- Assignees (ticket and subtask) must be **members of that team**

### Seeded tickets (`DEV-1` … `DEV-6`)

From `data/devops_tickets.json` — ECS health checks, CI/CD pipeline epic, Postgres pool tuning, and more. Log in as `livingdevops` to see them.

### Typical workflow

```text
1. Teams → Create Team (project key OPS)
2. Add members (single or bulk CSV)
3. Tickets → Create Ticket → select OPS team
4. Assign to a teammate, add subtasks and comments
5. Filter board by status, team, priority, assignee
```

---

## Project structure

```text
src/
├── app/
│   ├── __init__.py          # App factory, blueprints, startup seeding
│   ├── seed.py              # Admin/team/retro/ticket seed + migrations
│   ├── models/models.py     # SQLAlchemy models
│   ├── routes/
│   │   ├── routes.py        # Portal (dashboard, students, …)
│   │   ├── auth.py          # Login / register
│   │   ├── retro.py         # Retrospective boards
│   │   ├── teams.py         # Team CRUD + members + bulk import
│   │   ├── tickets.py       # Ticket CRUD + subtasks + comments
│   │   ├── team_helpers.py  # Team/ticket access helpers
│   │   └── helpers.py       # Auth guards, validation
│   ├── templates/           # Jinja2 HTML
│   └── static/styles.css
├── data/
│   ├── admins.json          # Seeded admin accounts
│   ├── devops_teams.json    # Seeded Platform DevOps team
│   ├── devops_retros.json   # Seeded retro boards + cards
│   └── devops_tickets.json  # Seeded sample tickets
├── tests/test_app.py        # 21 automated tests
├── docker-compose.yaml      # Postgres + app
├── Dockerfile
├── config.py                # DB_LINK env var
└── run.py                   # Gunicorn entrypoint
```

---

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `DB_LINK` | `sqlite:////tmp/student_portal.db` | Database URL |
| `SECRET_KEY` | dev-only placeholder | Flask session signing |
| `ADMIN_PASSWORD` | from `admins.json` | Override primary admin password |
| `DEVOPS_CAPTAIN_PASSWORD` | from `admins.json` | Override second admin password |

Docker Compose sets `DB_LINK=postgresql://postgres:password@postgres:5432/mydb`.

---

## Observability

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | JSON `{ "status": "healthy", "database": "connected" }` |
| `GET /metrics` | Prometheus metrics (request counts, durations) |

Structured JSON logging is enabled for each HTTP request.

---

## Common tasks

### I'm a new user — what do I do first?

1. **Register** at `/register`
2. Open **Retros** — seeded boards are ready to use
3. **Teams → Create Team** — set up your squad
4. **Tickets → Create Ticket** — assign work to teammates

### I can't create a retro

Only **admins** can create retros. Log in as `livingdevops` / `LivingDevops1!` or ask an admin for a join link to an existing board.

### I can't see any tickets

Tickets are **team-scoped**. Create or join a team first. Seeded `DEV-*` tickets are only visible to Platform DevOps members (the seeded admins).

### I want to onboard my whole team at once

1. Create your team
2. Open the team page → **Bulk Import Members**
3. Paste or upload CSV: `email,password,username`

---

## Deploy notes (ECS)

- Built from `Dockerfile` — Python 3.13, Gunicorn on port 8000
- Health check hits `/health`
- Postgres recommended for production (`DB_LINK`)
- Set `SECRET_KEY` and admin passwords via environment variables in ECS task definition
