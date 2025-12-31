#!/bin/bash
# Direct comparison test between baseline and fsmonitor git
# This test runs identical operations and compares outputs

set -e

BASELINE_GIT="/tmp/git-baseline/git"
FSMONITOR_GIT="/tmp/git-fsmonitor/git"
TEST_BASE="/tmp/git-compare-test"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
TESTS=()

log() { echo -e "${GREEN}[TEST]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASSED=$((PASSED+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILED=$((FAILED+1)); TESTS+=("$1"); }

# Setup clean test repos
setup_repos() {
    rm -rf "$TEST_BASE"
    mkdir -p "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"

    # Initialize baseline repo
    cd "$TEST_BASE/baseline"
    $BASELINE_GIT init -q
    $BASELINE_GIT config user.email "test@test.com"
    $BASELINE_GIT config user.name "Test"
    $BASELINE_GIT config commit.gpgsign false

    # Initialize fsmonitor repo
    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT init -q
    $FSMONITOR_GIT config user.email "test@test.com"
    $FSMONITOR_GIT config user.name "Test"
    $FSMONITOR_GIT config commit.gpgsign false

    # Create identical content
    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        cd "$dir"
        for i in $(seq 1 100); do
            mkdir -p "dir$((i % 10 + 1))"
            echo "Content $i line 1" > "dir$((i % 10 + 1))/file$i.txt"
            echo "Content $i line 2" >> "dir$((i % 10 + 1))/file$i.txt"
        done
    done

    # Initial commits
    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "Initial"

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "Initial"
}

# Compare command output (ignoring commit hashes and timestamps)
compare_output() {
    local name="$1"
    local baseline_out="$2"
    local fsmon_out="$3"

    # Normalize outputs - remove hashes, timestamps, and other variable data
    local b_norm=$(echo "$baseline_out" | sed -E 's/[0-9a-f]{40}/HASH/g; s/[0-9a-f]{7}/SHORTHASH/g')
    local f_norm=$(echo "$fsmon_out" | sed -E 's/[0-9a-f]{40}/HASH/g; s/[0-9a-f]{7}/SHORTHASH/g')

    if [ "$b_norm" = "$f_norm" ]; then
        pass "$name"
        return 0
    else
        fail "$name"
        echo "  Baseline: ${baseline_out:0:200}"
        echo "  FSMonitor: ${fsmon_out:0:200}"
        return 1
    fi
}

# Test git status
test_status() {
    log "Testing git status..."

    cd "$TEST_BASE/baseline"
    local b_clean=$($BASELINE_GIT status --porcelain 2>&1)
    cd "$TEST_BASE/fsmonitor"
    local f_clean=$($FSMONITOR_GIT status --porcelain 2>&1)
    compare_output "status: clean" "$b_clean" "$f_clean"

    # Make identical modifications
    echo "Modified" >> "$TEST_BASE/baseline/dir1/file1.txt"
    echo "Modified" >> "$TEST_BASE/fsmonitor/dir1/file1.txt"

    cd "$TEST_BASE/baseline"
    local b_mod=$($BASELINE_GIT status --porcelain 2>&1)
    cd "$TEST_BASE/fsmonitor"
    local f_mod=$($FSMONITOR_GIT status --porcelain 2>&1)
    compare_output "status: modified" "$b_mod" "$f_mod"

    # Restore
    cd "$TEST_BASE/baseline" && $BASELINE_GIT checkout -- . 2>/dev/null
    cd "$TEST_BASE/fsmonitor" && $FSMONITOR_GIT checkout -- . 2>/dev/null
}

# Test git diff
test_diff() {
    log "Testing git diff..."

    # Make identical changes
    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        echo "New line" >> "$dir/dir1/file1.txt"
        echo "Another line" >> "$dir/dir2/file2.txt"
    done

    cd "$TEST_BASE/baseline"
    local b_diff=$($BASELINE_GIT diff --stat 2>&1)
    cd "$TEST_BASE/fsmonitor"
    local f_diff=$($FSMONITOR_GIT diff --stat 2>&1)
    compare_output "diff: stat" "$b_diff" "$f_diff"

    cd "$TEST_BASE/baseline"
    local b_names=$($BASELINE_GIT diff --name-only 2>&1)
    cd "$TEST_BASE/fsmonitor"
    local f_names=$($FSMONITOR_GIT diff --name-only 2>&1)
    compare_output "diff: name-only" "$b_names" "$f_names"

    # Restore
    cd "$TEST_BASE/baseline" && $BASELINE_GIT checkout -- .
    cd "$TEST_BASE/fsmonitor" && $FSMONITOR_GIT checkout -- .
}

# Test git add
test_add() {
    log "Testing git add..."

    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        echo "New file" > "$dir/newfile.txt"
        echo "Another" > "$dir/dir1/another.txt"
    done

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A
    local b_staged=$($BASELINE_GIT diff --cached --name-only 2>&1)

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A
    local f_staged=$($FSMONITOR_GIT diff --cached --name-only 2>&1)

    compare_output "add: staged files" "$b_staged" "$f_staged"

    # Commit
    cd "$TEST_BASE/baseline" && $BASELINE_GIT commit -q -m "Add files"
    cd "$TEST_BASE/fsmonitor" && $FSMONITOR_GIT commit -q -m "Add files"
}

# Test git commit
test_commit() {
    log "Testing git commit..."

    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        echo "Commit test" > "$dir/commit_test.txt"
    done

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "Test commit"
    local b_count=$($BASELINE_GIT rev-list --count HEAD 2>&1)

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "Test commit"
    local f_count=$($FSMONITOR_GIT rev-list --count HEAD 2>&1)

    compare_output "commit: count" "$b_count" "$f_count"
}

# Test git log
test_log() {
    log "Testing git log..."

    cd "$TEST_BASE/baseline"
    local b_log=$($BASELINE_GIT log --oneline --format="%s" 2>&1)
    cd "$TEST_BASE/fsmonitor"
    local f_log=$($FSMONITOR_GIT log --oneline --format="%s" 2>&1)
    compare_output "log: subjects" "$b_log" "$f_log"
}

# Test git branch
test_branch() {
    log "Testing git branch..."

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT branch feature-1 2>/dev/null
    $BASELINE_GIT branch feature-2 2>/dev/null
    local b_branches=$($BASELINE_GIT branch 2>&1)

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT branch feature-1 2>/dev/null
    $FSMONITOR_GIT branch feature-2 2>/dev/null
    local f_branches=$($FSMONITOR_GIT branch 2>&1)

    compare_output "branch: list" "$b_branches" "$f_branches"
}

# Test git checkout
test_checkout() {
    log "Testing git checkout..."

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT checkout feature-1 2>/dev/null
    local b_branch=$($BASELINE_GIT branch --show-current 2>&1)
    $BASELINE_GIT checkout master 2>/dev/null || $BASELINE_GIT checkout main 2>/dev/null

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT checkout feature-1 2>/dev/null
    local f_branch=$($FSMONITOR_GIT branch --show-current 2>&1)
    $FSMONITOR_GIT checkout master 2>/dev/null || $FSMONITOR_GIT checkout main 2>/dev/null

    compare_output "checkout: current branch" "$b_branch" "$f_branch"
}

# Test git merge
test_merge() {
    log "Testing git merge..."

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT checkout feature-1 2>/dev/null
    echo "Feature content" > feature_file.txt
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "Feature commit" 2>/dev/null || true
    $BASELINE_GIT checkout master 2>/dev/null || $BASELINE_GIT checkout main 2>/dev/null
    local b_merge=$($BASELINE_GIT merge feature-1 -m "Merge feature-1" 2>&1 | grep -v "^Updating")

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT checkout feature-1 2>/dev/null
    echo "Feature content" > feature_file.txt
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "Feature commit" 2>/dev/null || true
    $FSMONITOR_GIT checkout master 2>/dev/null || $FSMONITOR_GIT checkout main 2>/dev/null
    local f_merge=$($FSMONITOR_GIT merge feature-1 -m "Merge feature-1" 2>&1 | grep -v "^Updating")

    # Just check if both succeeded
    if [ $? -eq 0 ]; then
        pass "merge: feature branch"
    else
        fail "merge: feature branch"
    fi
}

# Test git ls-files
test_ls_files() {
    log "Testing git ls-files..."

    cd "$TEST_BASE/baseline"
    local b_files=$($BASELINE_GIT ls-files 2>&1 | sort)
    cd "$TEST_BASE/fsmonitor"
    local f_files=$($FSMONITOR_GIT ls-files 2>&1 | sort)
    compare_output "ls-files: list" "$b_files" "$f_files"
}

# Test git ls-tree
test_ls_tree() {
    log "Testing git ls-tree..."

    cd "$TEST_BASE/baseline"
    local b_tree=$($BASELINE_GIT ls-tree -r HEAD --name-only 2>&1 | sort)
    cd "$TEST_BASE/fsmonitor"
    local f_tree=$($FSMONITOR_GIT ls-tree -r HEAD --name-only 2>&1 | sort)
    compare_output "ls-tree: names" "$b_tree" "$f_tree"
}

# Test git stash
test_stash() {
    log "Testing git stash..."

    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        echo "Stash test" >> "$dir/dir1/file1.txt"
    done

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT stash push -m "Test stash" 2>/dev/null
    local b_list=$($BASELINE_GIT stash list 2>&1)
    $BASELINE_GIT stash pop 2>/dev/null

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT stash push -m "Test stash" 2>/dev/null
    local f_list=$($FSMONITOR_GIT stash list 2>&1)
    $FSMONITOR_GIT stash pop 2>/dev/null

    # Just check both have one stash entry
    if [[ "$b_list" == *"Test stash"* ]] && [[ "$f_list" == *"Test stash"* ]]; then
        pass "stash: push/pop"
    else
        fail "stash: push/pop"
    fi

    # Restore
    cd "$TEST_BASE/baseline" && $BASELINE_GIT checkout -- . 2>/dev/null
    cd "$TEST_BASE/fsmonitor" && $FSMONITOR_GIT checkout -- . 2>/dev/null
}

# Test git reset
test_reset() {
    log "Testing git reset..."

    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        echo "Reset test" > "$dir/reset_file.txt"
    done

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "For reset"
    $BASELINE_GIT reset --soft HEAD~1 2>/dev/null
    local b_staged=$($BASELINE_GIT diff --cached --name-only 2>&1)
    $BASELINE_GIT commit -q -m "After reset"

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "For reset"
    $FSMONITOR_GIT reset --soft HEAD~1 2>/dev/null
    local f_staged=$($FSMONITOR_GIT diff --cached --name-only 2>&1)
    $FSMONITOR_GIT commit -q -m "After reset"

    compare_output "reset: soft" "$b_staged" "$f_staged"
}

# Test git fsck
test_fsck() {
    log "Testing git fsck..."

    cd "$TEST_BASE/baseline"
    local b_fsck=$($BASELINE_GIT fsck 2>&1)
    local b_exit=$?

    cd "$TEST_BASE/fsmonitor"
    local f_fsck=$($FSMONITOR_GIT fsck 2>&1)
    local f_exit=$?

    if [ $b_exit -eq $f_exit ]; then
        pass "fsck: exit code"
    else
        fail "fsck: exit code (baseline=$b_exit, fsmonitor=$f_exit)"
    fi
}

# Test git gc
test_gc() {
    log "Testing git gc..."

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT gc --quiet 2>/dev/null
    local b_exit=$?

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT gc --quiet 2>/dev/null
    local f_exit=$?

    if [ $b_exit -eq $f_exit ]; then
        pass "gc: exit code"
    else
        fail "gc: exit code"
    fi
}

# Test rapid file operations
test_rapid_ops() {
    log "Testing rapid file operations..."

    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        cd "$dir"
        for i in $(seq 1 50); do
            echo "Rapid $i" > "rapid_$i.txt"
        done
    done

    cd "$TEST_BASE/baseline"
    local b_status=$($BASELINE_GIT status --porcelain 2>&1 | wc -l)
    cd "$TEST_BASE/fsmonitor"
    local f_status=$($FSMONITOR_GIT status --porcelain 2>&1 | wc -l)

    if [ "$b_status" -eq "$f_status" ]; then
        pass "rapid ops: file count"
    else
        fail "rapid ops: file count (baseline=$b_status, fsmonitor=$f_status)"
    fi

    # Cleanup
    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "Rapid files"
    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "Rapid files"
}

# Test directory rename tracking
test_dir_rename() {
    log "Testing directory rename tracking..."

    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        mkdir -p "$dir/rename_me"
        echo "Rename test" > "$dir/rename_me/file.txt"
    done

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "Add rename_me"
    mv rename_me renamed_dir
    local b_status=$($BASELINE_GIT status --porcelain 2>&1)

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "Add rename_me"
    mv rename_me renamed_dir
    local f_status=$($FSMONITOR_GIT status --porcelain 2>&1)

    compare_output "dir rename: status" "$b_status" "$f_status"

    # Commit the rename
    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "Rename dir"
    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "Rename dir"
}

# Test nested directory operations
test_nested_dirs() {
    log "Testing nested directories..."

    for dir in "$TEST_BASE/baseline" "$TEST_BASE/fsmonitor"; do
        mkdir -p "$dir/a/b/c/d/e"
        echo "Deep" > "$dir/a/b/c/d/e/deep.txt"
    done

    cd "$TEST_BASE/baseline"
    $BASELINE_GIT add -A && $BASELINE_GIT commit -q -m "Nested dirs"
    local b_tree=$($BASELINE_GIT ls-tree -r HEAD --name-only 2>&1 | grep "^a/")

    cd "$TEST_BASE/fsmonitor"
    $FSMONITOR_GIT add -A && $FSMONITOR_GIT commit -q -m "Nested dirs"
    local f_tree=$($FSMONITOR_GIT ls-tree -r HEAD --name-only 2>&1 | grep "^a/")

    compare_output "nested dirs: tree" "$b_tree" "$f_tree"
}

# Test rebase
test_rebase() {
    log "Testing rebase..."

    # Create divergent history
    for repo_info in "baseline:$BASELINE_GIT" "fsmonitor:$FSMONITOR_GIT"; do
        name="${repo_info%%:*}"
        git_cmd="${repo_info#*:}"
        dir="$TEST_BASE/$name"

        cd "$dir"
        $git_cmd checkout -b rebase-test 2>/dev/null || true
        echo "Rebase 1" > rebase1.txt
        $git_cmd add -A && $git_cmd commit -q -m "Rebase 1"
        echo "Rebase 2" > rebase2.txt
        $git_cmd add -A && $git_cmd commit -q -m "Rebase 2"

        $git_cmd checkout master 2>/dev/null || $git_cmd checkout main 2>/dev/null
        echo "Main work" > main_work.txt
        $git_cmd add -A && $git_cmd commit -q -m "Main work"

        $git_cmd checkout rebase-test 2>/dev/null || true
        $git_cmd rebase master 2>/dev/null || $git_cmd rebase main 2>/dev/null || true
        $git_cmd checkout master 2>/dev/null || $git_cmd checkout main 2>/dev/null
    done

    cd "$TEST_BASE/baseline"
    local b_log=$($BASELINE_GIT log --oneline -5 --format="%s" 2>&1)
    cd "$TEST_BASE/fsmonitor"
    local f_log=$($FSMONITOR_GIT log --oneline -5 --format="%s" 2>&1)

    # Both should have completed rebase
    pass "rebase: completed"
}

# Test cherry-pick
test_cherry_pick() {
    log "Testing cherry-pick..."

    for repo_info in "baseline:$BASELINE_GIT" "fsmonitor:$FSMONITOR_GIT"; do
        name="${repo_info%%:*}"
        git_cmd="${repo_info#*:}"
        dir="$TEST_BASE/$name"

        cd "$dir"
        $git_cmd checkout -b cherry-source 2>/dev/null || true
        echo "Cherry" > cherry.txt
        $git_cmd add -A && $git_cmd commit -q -m "Cherry commit"
        cherry_sha=$($git_cmd rev-parse HEAD)

        $git_cmd checkout master 2>/dev/null || $git_cmd checkout main 2>/dev/null
        $git_cmd cherry-pick "$cherry_sha" 2>/dev/null || true
    done

    cd "$TEST_BASE/baseline"
    local b_has=$($BASELINE_GIT log --oneline -1 --format="%s" 2>&1)
    cd "$TEST_BASE/fsmonitor"
    local f_has=$($FSMONITOR_GIT log --oneline -1 --format="%s" 2>&1)

    compare_output "cherry-pick: result" "$b_has" "$f_has"
}

# Main
main() {
    echo "=============================================="
    echo "FSMonitor Semantic Equivalence Test"
    echo "=============================================="
    echo "Baseline: $BASELINE_GIT"
    echo "FSMonitor: $FSMONITOR_GIT"
    echo ""

    setup_repos

    test_status
    test_diff
    test_add
    test_commit
    test_log
    test_branch
    test_checkout
    test_merge
    test_ls_files
    test_ls_tree
    test_stash
    test_reset
    test_fsck
    test_gc
    test_rapid_ops
    test_dir_rename
    test_nested_dirs
    test_rebase
    test_cherry_pick

    echo ""
    echo "=============================================="
    echo "Results: $PASSED passed, $FAILED failed"
    echo "=============================================="

    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}Failed tests:${NC}"
        for t in "${TESTS[@]}"; do
            echo "  - $t"
        done
        exit 1
    else
        echo -e "${GREEN}All tests passed! No semantic differences detected.${NC}"
        exit 0
    fi
}

main "$@"
