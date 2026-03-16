#!/bin/bash

# Script to update ADR files with consistent front matter and links

cd "$(dirname "$0")/../docs/adr" || exit 1

# Function to update links in a file
update_links() {
    local file="$1"
    # Remove .md extensions from internal links
    sed -i 's/\]\([^)]*\)\.md)/\]\1)/g' "$file"
    # Update relative links to documentation
    sed -i 's|\.\./\([^)]*\)\.md|\.\./\1|g' "$file"
    # Update title format in front matter
    sed -i '/^title:/c\title: "ADR-'"$(basename "$file" .md)"': '"$(head -n 1 "$file" | sed 's/^# ADR-[0-9]*: //')"'"' "$file"
}

# Process each ADR file
for file in [0-9]*.md; do
    if [ -f "$file" ]; then
        echo "Updating links in $file"
        update_links "$file"
        
        # Ensure standard Related section exists
        if ! grep -q "^## Related" "$file"; then
            echo "Adding Related section to $file"
            cat >> "$file" << EOF

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)
EOF
        fi
    fi
done

echo "ADR link update complete" 