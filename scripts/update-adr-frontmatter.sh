#!/bin/bash

# Script to add Jekyll front matter to ADR files

cd "$(dirname "$0")/../docs/adr" || exit 1

for file in [0-9]*.md; do
    if [ -f "$file" ]; then
        # Skip if front matter already exists
        if grep -q "^---" "$file"; then
            echo "Skipping $file - front matter already exists"
            continue
        fi

        # Get the title from the first heading
        title=$(head -n 1 "$file" | sed 's/^# //')
        
        # Create temporary file
        tmp_file=$(mktemp)
        
        # Add front matter
        cat > "$tmp_file" << EOF
---
layout: default
title: "ADR-${file%%.md}: ${title#* }"
description: "Architecture Decision Record for ${title#* }"
---

EOF

        # Append original content
        cat "$file" >> "$tmp_file"
        
        # Replace original file
        mv "$tmp_file" "$file"
        echo "Updated $file"
    fi
done

echo "ADR front matter update complete" 