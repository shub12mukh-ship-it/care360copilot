# CARE360 Copilot

CARE360 Copilot is a Snowflake-based healthcare analytics solution built using:

- Snowflake Workspaces
- Snowflake Cortex Agent
- Snowflake Streamlit
- CARE360 Database
- Git-based source control

This repository contains the source code, agent configuration, sample datasets, documentation, and SQL objects used by the CARE360 application.

---

# Repository Structure

```text
care360copilot/
├── app/
├── data/
├── docs/
├── documents/
├── scripts/
├── sql/
├── agent_spec.yaml
├── requirements.txt
└── README.md
```

---

# Access Requirements

Each team member must have:

- Access to the Git repository
- A Snowflake user account
- Access to CARE360 database and schema
- Access to the warehouse
- Access to the Streamlit application
- Access to the Cortex Agent
- Assigned Snowflake role (e.g. CARE360_DEV_ROLE)

---

# Initial Setup

## 1. Clone the Repository

```bash
git clone <repository-url>
cd care360copilot
```

## 2. Login to Snowflake

Open:

```text
https://<account>.snowflakecomputing.com
```

## 3. Verify Role Access

```sql
SELECT CURRENT_ROLE();
```

If required:

```sql
USE ROLE CARE360_DEV_ROLE;
```

---

# Accessing CARE360 Database

```sql
SHOW SCHEMAS IN DATABASE CARE360_DB;
SHOW TABLES IN SCHEMA CARE360_DB.PUBLIC;
```

Example:

```sql
SELECT * FROM PATIENTS LIMIT 10;
```

---

# Accessing the Streamlit Application

Navigate to:

```text
Projects
→ Streamlit Apps
→ PATIENTCARE360
```

---

# Accessing the Cortex Agent

Navigate to:

```text
AI & ML
→ Agents
→ CARE360 Agent
```

Agent configuration is stored in:

```text
agent_spec.yaml
```

---

# Snowflake Workspaces

Navigate to:

```text
Workspaces
```

You may see:

```text
TeamWorkspace
```

Note: Workspaces are not automatically shared with all users. If you cannot see the workspace, use the Git repository workflow.

---

# How Team Members Modify Files

## Recommended: Git Repository

Create a branch:

```bash
git checkout -b feature/my-change
```

Commit changes:

```bash
git add .
git commit -m "My changes"
git push
```

Submit a Pull Request for review.

## Alternative: Shared Snowflake Workspace

If the workspace is visible to you:

1. Open Workspaces.
2. Open TeamWorkspace.
3. Open the CARE360 project.
4. Edit files directly in Snowflake.

---

# Verification

```sql
SELECT CURRENT_ROLE();
SHOW DATABASES;
SHOW SCHEMAS;
SHOW STREAMLITS;
```

---

# Team Onboarding Checklist

- [ ] Snowflake account provisioned
- [ ] CARE360 role assigned
- [ ] Git repository access granted
- [ ] Repository cloned
- [ ] Database access verified
- [ ] Streamlit app access verified
- [ ] Cortex Agent access verified
- [ ] Development branch created
