#!/bin/bash

# Usage:
#   ./clean_merged_branches.sh        → 互動刪除模式
#   ./clean_merged_branches.sh -y     → 自動刪除所有已 merge branch（跳過保護分支）

AUTO_YES=false
if [[ "$1" == "-y" ]]; then
    AUTO_YES=true
fi

# 保護不要刪的分支
PROTECTED_BRANCHES=("main" "master" "develop" "dev")

echo "🔍 Checking merged branches..."

MERGED_BRANCHES=$(git branch --merged | sed 's/\*//g' | awk '{$1=$1};1')

if [ -z "$MERGED_BRANCHES" ]; then
    echo "✔ No merged branches found."
    exit 0
fi

echo "📌 Merged branches:"
echo "$MERGED_BRANCHES"
echo ""

for BRANCH in $MERGED_BRANCHES; do
    # 保護主要分支
    if [[ " ${PROTECTED_BRANCHES[*]} " =~ " ${BRANCH} " ]]; then
        echo "⛔ Protecting branch '${BRANCH}' (skipped)"
        continue
    fi

    if [[ -z "$BRANCH" ]]; then
        continue
    fi

    # 決定是否自動 yes
    if $AUTO_YES; then
        CONFIRM="y"
        echo "⚡ Auto-delete enabled (-y): deleting '${BRANCH}'..."
    else
        echo -n "❓ Delete branch '${BRANCH}' (local + remote)? [y/N]: "
        read -r CONFIRM
    fi

    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        echo "🗑 Deleting local branch '${BRANCH}'..."
        git branch -d "$BRANCH"

        echo "🔎 Checking remote branch 'origin/${BRANCH}'..."
        if git ls-remote --heads origin "$BRANCH" > /dev/null 2>&1; then
            echo "🗑 Deleting remote branch '${BRANCH}'..."
            git push origin --delete "$BRANCH"
        else
            echo "ℹ️  Remote branch 'origin/${BRANCH}' does not exist, skip remote delete."
        fi

        echo "----"
    else
        echo "⏭ Skipped '${BRANCH}'"
    fi
done

echo "🔄 Pruning stale remote references..."
git fetch -p

echo "🎉 Done!"
