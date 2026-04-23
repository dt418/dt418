#!/usr/bin/env bash
set -euo pipefail

export GH_TOKEN=$(gh auth token)

python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import re
import base64
from datetime import datetime, timedelta, timezone
from collections import Counter

def gh_api(path, paginate=False):
    cmd = ["gh", "api", path]
    if paginate:
        cmd.append("--paginate")
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    return data if isinstance(data, list) else [data]

def get_repo_file(repo, filepath):
    """Get file content from a repo"""
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/dt418/{repo}/contents/{filepath}", "--jq", ".content"],
            capture_output=True, text=True, check=True
        )
        return base64.b64decode(result.stdout.strip()).decode("utf-8")
    except:
        return None

def extract_deps_from_repo(repo):
    """Extract dependencies from package.json or composer.json"""
    deps = set()
    
    # Check package.json
    content = get_repo_file(repo, "package.json")
    if content:
        try:
            pkg = json.loads(content)
            all_deps = list(pkg.get("dependencies", {}).keys()) + list(pkg.get("devDependencies", {}).keys())
            for d in all_deps:
                deps.add(d)  # Keep full name including @scope/
        except:
            pass
    
    # Check composer.json
    content = get_repo_file(repo, "composer.json")
    if content:
        try:
            pkg = json.loads(content)
            for d in list(pkg.get("require", {}).keys()) + list(pkg.get("require-dev", {}).keys()):
                deps.add(d)
        except:
            pass
    
    return deps

# Tech mapping: exact package name -> (display_name, color, logo, logo_color)
TECH_BADGES = {
    "react": ("React", "61DAFB", "react", "black"),
    "next": ("Next.js", "000000", "next.js", "white"),
    "typescript": ("TypeScript", "3178C6", "typescript", "white"),
    "vite": ("Vite", "646CFF", "vite", "white"),
    "tailwindcss": ("Tailwind CSS", "06B6D4", "tailwindcss", "white"),
    "@tanstack/react-query": ("TanStack Query", "FF4154", "reactquery", "white"),
    "zustand": ("Zustand", "000000", None, "white"),
    "react-hook-form": ("React Hook Form", "EC5990", "reacthookform", "white"),
    "zod": ("Zod", "3E67B1", None, "white"),
    "framer-motion": ("Framer Motion", "0055FF", "framer", "white"),
    "@radix-ui/react-slot": ("Radix UI", "161718", "radixui", "white"),
    "vitest": ("Vitest", "6E9F18", "vitest", "white"),
    "@testing-library/react": ("Testing Library", "E33332", "testinglibrary", "white"),
    "eslint": ("ESLint", "4B32C3", "eslint", "white"),
    "prettier": ("Prettier", "F7B93E", "prettier", "black"),
    "turbo": ("Turbo", "EF4444", "turborepo", "white"),
    "laravel/framework": ("Laravel", "FF2D20", "laravel", "white"),
    "filament/filament": ("Filament", "FDAE4B", "laravel", "white"),
    "php": ("PHP", "777BB4", "php", "white"),
    "docker": ("Docker", "2496ED", "docker", "white"),
}

# Fetch user data
user = gh_api("user")[0]
public_repos = user["public_repos"]
followers = user["followers"]
created = datetime.fromisoformat(user["created_at"].replace("Z", "+00:00"))
years = (datetime.now(timezone.utc) - created).days // 365

# Fetch all non-fork repos
all_repos = gh_api("users/dt418/repos", paginate=True)
repos = [r for r in all_repos if not r["fork"] and r["name"] != "dt418"]

# Scan dependencies from all repos (skip config-only repos)
repos_to_scan = [r["name"] for r in repos if r["language"] in ("TypeScript", "JavaScript", "PHP", "Python", "Go", "Rust", "Ruby")]
all_deps = set()
repo_languages = set()
for repo_name in repos_to_scan:
    all_deps.update(extract_deps_from_repo(repo_name))
    # Find the repo object for language
    for r in repos:
        if r["name"] == repo_name and r["language"]:
            repo_languages.add(r["language"])
            break

# Add languages as detected tech
if "TypeScript" in repo_languages:
    all_deps.add("typescript")
if "JavaScript" in repo_languages:
    all_deps.add("vite")  # JS repos often use vite, but we already have it from deps

# Build tech stack badges from detected deps
detected_tech = []
for dep, (name, color, logo, logoColor) in TECH_BADGES.items():
    if dep in all_deps:
        if logo:
            detected_tech.append(f'<img src="https://img.shields.io/badge/{name.replace(" ", "_")}-{color}?style=flat&logo={logo}&logoColor={logoColor}" alt="{name}" />')
        else:
            detected_tech.append(f'<img src="https://img.shields.io/badge/{name.replace(" ", "_")}-{color}?style=flat&logoColor={logoColor}" alt="{name}" />')

tech_stack_html = "\n  ".join(detected_tech) if detected_tech else "*No tech detected*"

# About Me - detect from actual usage
has_laravel = "laravel/framework" in all_deps
has_filament = "filament/filament" in all_deps
has_nextjs = "next" in all_deps
has_react = "react" in all_deps

about_lines = []
if has_react or has_nextjs:
    about_lines.append("- 🏢 Building with **React, Next.js, TypeScript, Tailwind CSS**")
if has_laravel:
    about_lines.append("- 🔧 Backend experience with **Laravel, PHP" + (", Filament" if has_filament else "") + "**")
about_lines.append("- 📫 Reach me at **danhthanh418@gmail.com**")
about_lines.append("- 🟢 Available for hire")
about_html = "\n".join(about_lines)

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

# Released projects: repos with stars
released = sorted([r for r in repos if r["stargazers_count"] > 0], key=lambda r: r["stargazers_count"], reverse=True)
released_table = "| Project | Language | ⭐ | Description |\n|---------|----------|----|-------------|"
for r in released[:6]:
    lang = r["language"] or "—"
    desc = (r.get("description") or "—").replace("|", "\\|")
    released_table += f"\n| [{r['name']}]({r['html_url']}) | {lang} | {r['stargazers_count']} | {desc} |"

# Top projects by stars
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
    r'<!-- ABOUT:START -->.*?<!-- ABOUT:END -->',
    f'<!-- ABOUT:START -->\n{about_html}\n<!-- ABOUT:END -->',
    content, flags=re.DOTALL
)

content = re.sub(
    r'<!-- TECH:START -->.*?<!-- TECH:END -->',
    f'<!-- TECH:START -->\n<p align="left">\n  {tech_stack_html}\n</p>\n<!-- TECH:END -->',
    content, flags=re.DOTALL
)

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
