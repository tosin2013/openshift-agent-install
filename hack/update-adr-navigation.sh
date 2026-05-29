#!/bin/bash
# update-adr-navigation.sh
# Add proper navigation frontmatter to all ADR files for Jekyll/Just-the-Docs

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

ADR_DIR="docs/adr"

echo "============================================================================"
echo "Updating ADR Navigation Structure"
echo "============================================================================"
echo ""

updated_count=0

# Process each ADR file (excluding index.md)
for adr_file in ${ADR_DIR}/[0-9]*.md; do
  if [ ! -f "$adr_file" ]; then
    continue
  fi

  filename=$(basename "$adr_file")
  adr_number=$(echo "$filename" | grep -o '^[0-9]\+')

  # Extract title from first heading in file (after frontmatter if it exists)
  title=$(grep -m 1 "^# " "$adr_file" | sed 's/^# //' | sed 's/ADR-[0-9]*: //')

  if [ -z "$title" ]; then
    echo "⚠️  $filename - No title found, skipping"
    continue
  fi

  echo "Processing: $filename"
  echo "  Number: $adr_number"
  echo "  Title: $title"

  # Check if file already has frontmatter
  if head -1 "$adr_file" | grep -q "^---$"; then
    echo "  ℹ️  Already has frontmatter, updating..."

    # Backup
    cp "$adr_file" "${adr_file}.bak"

    # Remove existing frontmatter (everything between first two --- markers)
    # and keep the rest of the content
    awk '/^---$/{if(++count==2) flag=1; next} flag' "$adr_file" > "${adr_file}.tmp"

    # Add new frontmatter
    cat > "$adr_file" <<EOF
---
layout: default
title: "ADR-${adr_number}: ${title}"
parent: ADRs
nav_order: ${adr_number}
---

EOF

    # Append the content
    cat "${adr_file}.tmp" >> "$adr_file"
    rm "${adr_file}.tmp"

  else
    echo "  ➕ Adding frontmatter..."

    # Backup
    cp "$adr_file" "${adr_file}.bak"

    # Create temp file with frontmatter
    cat > "${adr_file}.new" <<EOF
---
layout: default
title: "ADR-${adr_number}: ${title}"
parent: ADRs
nav_order: ${adr_number}
---

EOF

    # Append original content
    cat "$adr_file" >> "${adr_file}.new"
    mv "${adr_file}.new" "$adr_file"
  fi

  echo "  ✅ Updated"
  echo ""
  updated_count=$((updated_count + 1))
done

echo "============================================================================"
echo "Summary"
echo "============================================================================"
echo "Updated: $updated_count ADR files"
echo "Backup files created: ${ADR_DIR}/*.bak"
echo ""
echo "Next steps:"
echo "1. Review changes: git diff docs/adr/"
echo "2. Test locally: bundle exec jekyll serve"
echo "3. Commit: git add docs/adr/ && git commit -m 'docs: Add navigation to ADRs'"
echo "4. Remove backups: rm docs/adr/*.bak"
echo "============================================================================"
