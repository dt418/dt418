#!/usr/bin/env bash
set -euo pipefail

README="README.md"

# Fetch user data
USER=$(gh api user)
export PUBLIC_REPOS=$(echo "$USER" | jq -r '.public_repos')
export FOLLOWERS=$(echo "$USER" | jq -r '.followers')
CREATED=$(echo "$USER" | jq -r '.created_at')
export YEARS=$(python3 -c "
from datetime import datetime
created = datetime.fromisoformat('${CREATED}'.replace('Z', '+00:00'))
years = (datetime.now(created.tzinfo) - created).days // 365
print(years)
")

# Fetch top repos (non-fork, sorted by stars)
TOP_REPOS=$(gh api users/dt418/repos?per_page=100 --jq '[.[] | select(.fork == false)] | sort_by(-.stargazers_count) | .[0:6]')
export PROJECTS_TABLE=$(echo "$TOP_REPOS" | jq -r '
  ["| Project | Language | ⭐ |", "|---------|----------|----|"] +
  [.[] | "| [\(.name)](\(.html_url)) | \(.language // "—") | \(.stargazers_count) |"] | join("\n")
')

# Fetch language stats
export LANG_STATS=$(gh api users/dt418/repos --paginate --jq '
  [.[] | select(.fork == false) | .language // "Other"]
  | group_by(.)
  | map({name: .[0], count: length})
  | sort_by(-.count)
  | .[0:5]
  | map("\(.name) (\(.count))")
  | join(", ")
')

# Update README using Python for reliable string replacement
python3 << 'PYTHON_SCRIPT'
import re
import os
from datetime import datetime

public_repos = os.environ['PUBLIC_REPOS']
followers = os.environ['FOLLOWERS']
years = os.environ['YEARS']
projects_table = os.environ['PROJECTS_TABLE']
lang_stats = os.environ['LANG_STATS']

with open('README.md', 'r') as f:
    content = f.read()

# Update counters
content = re.sub(r'id="repos-count">\d+</span>', f'id="repos-count">{public_repos}</span>', content)
content = re.sub(r'id="followers-count">\d+</span>', f'id="followers-count">{followers}</span>', content)
content = re.sub(r'id="years-count">\d+</span>', f'id="years-count">{years}</span>', content)
content = re.sub(r'id="lang-stats">[^<]*</span>', f'id="lang-stats">{lang_stats}</span>', content)

# Update projects table
pattern = r'<!-- PROJECTS:START -->.*?<!-- PROJECTS:END -->'
replacement = f'<!-- PROJECTS:START -->\n{projects_table}\n<!-- PROJECTS:END -->'
content = re.sub(pattern, replacement, content, flags=re.DOTALL)

# Update timestamp
now = datetime.now().strftime('%B %Y')
content = re.sub(r'Last updated:.*?•', f'Last updated: {now} •', content)

with open('README.md', 'w') as f:
    f.write(content)

print("README updated successfully")
PYTHON_SCRIPT
