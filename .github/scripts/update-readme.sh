#!/usr/bin/env bash
set -euo pipefail

export GH_TOKEN=$(gh auth token)

python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import re
from datetime import datetime, timedelta, timezone

def gh_api_paginated(path):
    """Fetch all pages from GitHub API"""
    result = subprocess.run(
        ["gh", "api", path, "--paginate", "--jq", "."],
        capture_output=True, text=True, check=True
    )
    data = json.loads(result.stdout)
    return data if isinstance(data, list) else [data]

def gh_api(path):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)

# Fetch user data
user = gh_api("user")
public_repos = user["public_repos"]
followers = user["followers"]
created = datetime.fromisoformat(user["created_at"].replace("Z", "+00:00"))
years = (datetime.now(timezone.utc) - created).days // 365

# Fetch all non-fork repos
all_repos = gh_api_paginated("users/dt418/repos")
repos = [r for r in all_repos if not r["fork"] and r["name"] != "dt418"]

# Active projects: updated within last 30 days
thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
active = [r for r in repos if datetime.fromisoformat(r["updated_at"].replace("Z", "+00:00")) > thirty_days_ago]
active.sort(key=lambda r: r["updated_at"], reverse=True)

active_table = "| Project | Language | Last Updated |\n|---------|----------|-------------|"
for r in active[:5]:
    lang = r["language"] or "—"
    date = r["updated_at"][:10]
    active_table += f"\n| [{r['name']}]({r['html_url']}) | {lang} | {date} |"
if not active:
    active_table += "\n| *No active projects in the last 30 days* | | |"

# Released projects: repos with stars (shipped & getting traction)
released = sorted([r for r in repos if r["stargazers_count"] > 0], key=lambda r: r["stargazers_count"], reverse=True)
released_table = "| Project | Language | ⭐ | Description |\n|---------|----------|----|-------------|"
for r in released[:6]:
    lang = r["language"] or "—"
    desc = (r.get("description") or "—").replace("|", "\\|")
    released_table += f"\n| [{r['name']}]({r['html_url']}) | {lang} | {r['stargazers_count']} | {desc} |"

# Top projects by stars (for Featured section)
top = sorted(repos, key=lambda r: r["stargazers_count"], reverse=True)[:6]
top_table = "| Project | Language | ⭐ |\n|---------|----------|----|"
for r in top:
    lang = r["language"] or "—"
    top_table += f"\n| [{r['name']}]({r['html_url']}) | {lang} | {r['stargazers_count']} |"

# Language stats
lang_counts = {}
for r in repos:
    lang = r["language"] or "Other"
    lang_counts[lang] = lang_counts.get(lang, 0) + 1
lang_stats = ", ".join(f"{k} ({v})" for k, v in sorted(lang_counts.items(), key=lambda x: -x[1])[:5])

# Update README
with open("README.md", "r") as f:
    content = f.read()

content = re.sub(r'id="repos-count">\d+</span>', f'id="repos-count">{public_repos}</span>', content)
content = re.sub(r'id="followers-count">\d+</span>', f'id="followers-count">{followers}</span>', content)
content = re.sub(r'id="years-count">\d+</span>', f'id="years-count">{years}</span>', content)
content = re.sub(r'id="lang-stats">[^<]*</span>', f'id="lang-stats">{lang_stats}</span>', content)

content = re.sub(
    r'<!-- ACTIVE-PROJECTS:START -->.*?<!-- ACTIVE-PROJECTS:END -->',
    f'<!-- ACTIVE-PROJECTS:START -->\n{active_table}\n<!-- ACTIVE-PROJECTS:END -->',
    content, flags=re.DOTALL
)

content = re.sub(
    r'<!-- RELEASED-PROJECTS:START -->.*?<!-- RELEASED-PROJECTS:END -->',
    f'<!-- RELEASED-PROJECTS:START -->\n{released_table}\n<!-- RELEASED-PROJECTS:END -->',
    content, flags=re.DOTALL
)

content = re.sub(
    r'<!-- PROJECTS:START -->.*?<!-- PROJECTS:END -->',
    f'<!-- PROJECTS:START -->\n{top_table}\n<!-- PROJECTS:END -->',
    content, flags=re.DOTALL
)

now = datetime.now().strftime("%B %Y")
content = re.sub(r"Last updated:.*?•", f"Last updated: {now} •", content)

with open("README.md", "w") as f:
    f.write(content)

print("README updated successfully")
PYTHON_SCRIPT
