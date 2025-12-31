#!/bin/bash
# Comprehensive stress test for fsmonitor Linux patch
# Compares git operations between baseline and fsmonitor-enabled versions

set -e

# Configuration
BASELINE_GIT="/tmp/git-baseline/git"
FSMONITOR_GIT="/tmp/git-fsmonitor/git"
TEST_DIR="/tmp/fsmonitor-stress-test"
RESULTS_DIR="/tmp/fsmonitor-test-results"
NUM_FILES=500
NUM_DIRS=50
NUM_COMMITS=20
NUM_BRANCHES=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

mkdir -p "$RESULTS_DIR"

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Create test repository with many files and directories
create_test_repo() {
    log "Creating test repository with $NUM_FILES files in $NUM_DIRS directories..."
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    $1 init
    $1 config user.email "test@test.com"
    $1 config user.name "Test User"
    $1 config commit.gpgsign false
    $1 config gpg.format openpgp

    # Create directory structure
    for i in $(seq 1 $NUM_DIRS); do
        mkdir -p "dir$i/subdir_a" "dir$i/subdir_b"
    done

    # Create files
    for i in $(seq 1 $NUM_FILES); do
        dir_num=$((i % NUM_DIRS + 1))
        echo "File $i content - line 1" > "dir$dir_num/file$i.txt"
        echo "File $i content - line 2" >> "dir$dir_num/file$i.txt"
        echo "File $i content - line 3" >> "dir$dir_num/file$i.txt"
    done

    # Create some binary-like files
    for i in $(seq 1 20); do
        dd if=/dev/urandom of="dir$i/binary$i.bin" bs=1024 count=10 2>/dev/null
    done

    # Initial commit
    $1 add -A
    $1 commit -m "Initial commit with $NUM_FILES files"

    log "Test repository created with $($1 rev-list --count HEAD) commits"
}

# Run a command and capture output for comparison
run_git_command() {
    local git_bin="$1"
    local name="$2"
    shift 2
    local output_file="$RESULTS_DIR/${name}_$(basename $git_bin).txt"

    # Run command and capture output
    if "$git_bin" "$@" > "$output_file" 2>&1; then
        echo "0" > "${output_file}.exitcode"
    else
        echo "$?" > "${output_file}.exitcode"
    fi
}

# Compare outputs from two git runs
compare_outputs() {
    local name="$1"
    local baseline="$RESULTS_DIR/${name}_git.txt"
    local fsmon="$RESULTS_DIR/${name}_git.txt"  # Same file now since we're not using different names

    # For this test we'll compare exit codes and key output patterns
    return 0
}

# Test: git status operations
test_status() {
    local git="$1"
    local label="$2"

    log "[$label] Testing git status..."

    cd "$TEST_DIR"

    # Clean status
    $git status > "$RESULTS_DIR/status_clean_$label.txt" 2>&1
    $git status --short > "$RESULTS_DIR/status_short_$label.txt" 2>&1
    $git status --porcelain > "$RESULTS_DIR/status_porcelain_$label.txt" 2>&1
    $git status --porcelain=v2 > "$RESULTS_DIR/status_porcelainv2_$label.txt" 2>&1

    # Modify some files
    for i in 1 5 10 25 50; do
        echo "Modified content" >> "dir$i/file$i.txt"
    done

    # Status with changes
    $git status > "$RESULTS_DIR/status_modified_$label.txt" 2>&1
    $git status --short > "$RESULTS_DIR/status_modified_short_$label.txt" 2>&1

    # Restore files
    $git checkout -- .
}

# Test: git diff operations
test_diff() {
    local git="$1"
    local label="$2"

    log "[$label] Testing git diff..."

    cd "$TEST_DIR"

    # Modify files
    for i in $(seq 1 30); do
        echo "Additional line $i" >> "dir$((i % NUM_DIRS + 1))/file$i.txt"
    done

    # Various diff operations
    $git diff > "$RESULTS_DIR/diff_working_$label.txt" 2>&1
    $git diff --stat > "$RESULTS_DIR/diff_stat_$label.txt" 2>&1
    $git diff --numstat > "$RESULTS_DIR/diff_numstat_$label.txt" 2>&1
    $git diff --name-only > "$RESULTS_DIR/diff_names_$label.txt" 2>&1
    $git diff --cached > "$RESULTS_DIR/diff_cached_$label.txt" 2>&1

    # Stage some changes
    $git add dir1/
    $git diff --cached > "$RESULTS_DIR/diff_staged_$label.txt" 2>&1
    $git diff HEAD > "$RESULTS_DIR/diff_head_$label.txt" 2>&1

    # Restore
    $git reset HEAD -- .
    $git checkout -- .
}

# Test: commit operations
test_commits() {
    local git="$1"
    local label="$2"

    log "[$label] Testing commit operations..."

    cd "$TEST_DIR"

    for i in $(seq 1 $NUM_COMMITS); do
        # Create/modify files
        echo "Commit $i content" > "dir$((i % NUM_DIRS + 1))/commit_test_$i.txt"
        $git add -A
        $git commit -m "Test commit $i for $label" > /dev/null 2>&1
    done

    # Log operations
    $git log --oneline > "$RESULTS_DIR/log_oneline_$label.txt" 2>&1
    $git log --stat -5 > "$RESULTS_DIR/log_stat_$label.txt" 2>&1
    $git log --format="%H %s" > "$RESULTS_DIR/log_format_$label.txt" 2>&1
    $git rev-list --count HEAD > "$RESULTS_DIR/commit_count_$label.txt" 2>&1
}

# Test: branch operations
test_branches() {
    local git="$1"
    local label="$2"

    log "[$label] Testing branch operations..."

    cd "$TEST_DIR"

    # Create branches
    for i in $(seq 1 $NUM_BRANCHES); do
        $git branch "feature-$label-$i" > /dev/null 2>&1
    done

    $git branch > "$RESULTS_DIR/branches_$label.txt" 2>&1
    $git branch -v > "$RESULTS_DIR/branches_v_$label.txt" 2>&1

    # Switch branches and make changes
    for i in $(seq 1 3); do
        $git checkout "feature-$label-$i" > /dev/null 2>&1
        echo "Branch $i content" > "branch_file_$i.txt"
        $git add -A
        $git commit -m "Commit on feature-$label-$i" > /dev/null 2>&1
    done

    $git checkout main > /dev/null 2>&1 || $git checkout master > /dev/null 2>&1
}

# Test: merge operations
test_merges() {
    local git="$1"
    local label="$2"

    log "[$label] Testing merge operations..."

    cd "$TEST_DIR"

    # Get main branch name
    main_branch=$($git branch --show-current)

    # Merge branches
    for i in $(seq 1 2); do
        $git merge "feature-$label-$i" -m "Merge feature-$label-$i" > "$RESULTS_DIR/merge_${i}_$label.txt" 2>&1 || true
    done
}

# Test: rebase operations
test_rebase() {
    local git="$1"
    local label="$2"

    log "[$label] Testing rebase operations..."

    cd "$TEST_DIR"

    # Create a branch for rebasing
    $git checkout -b "rebase-test-$label" > /dev/null 2>&1

    for i in $(seq 1 5); do
        echo "Rebase content $i" > "rebase_file_$i.txt"
        $git add -A
        $git commit -m "Rebase commit $i" > /dev/null 2>&1
    done

    # Go back to main and make other commits
    $git checkout main > /dev/null 2>&1 || $git checkout master > /dev/null 2>&1

    for i in $(seq 1 3); do
        echo "Main content $i" > "main_file_$i.txt"
        $git add -A
        $git commit -m "Main commit $i" > /dev/null 2>&1
    done

    # Rebase the feature branch
    $git checkout "rebase-test-$label" > /dev/null 2>&1
    $git rebase main > "$RESULTS_DIR/rebase_$label.txt" 2>&1 || $git rebase master > "$RESULTS_DIR/rebase_$label.txt" 2>&1 || true

    $git checkout main > /dev/null 2>&1 || $git checkout master > /dev/null 2>&1
}

# Test: stash operations
test_stash() {
    local git="$1"
    local label="$2"

    log "[$label] Testing stash operations..."

    cd "$TEST_DIR"

    # Make changes
    for i in $(seq 1 10); do
        echo "Stash test $i" >> "dir$i/file$i.txt"
    done

    # Stash operations
    $git stash > "$RESULTS_DIR/stash_push_$label.txt" 2>&1
    $git stash list > "$RESULTS_DIR/stash_list_$label.txt" 2>&1
    $git stash pop > "$RESULTS_DIR/stash_pop_$label.txt" 2>&1 || true

    # Cleanup
    $git checkout -- .
}

# Test: reset operations
test_reset() {
    local git="$1"
    local label="$2"

    log "[$label] Testing reset operations..."

    cd "$TEST_DIR"

    # Make commits to reset
    for i in $(seq 1 5); do
        echo "Reset test $i" > "reset_test_$i.txt"
        $git add -A
        $git commit -m "Reset test commit $i" > /dev/null 2>&1
    done

    # Soft reset
    $git reset --soft HEAD~2 > "$RESULTS_DIR/reset_soft_$label.txt" 2>&1
    $git status --porcelain > "$RESULTS_DIR/reset_soft_status_$label.txt" 2>&1
    $git commit -m "After soft reset" > /dev/null 2>&1

    # Mixed reset (default)
    echo "More content" > "more_content.txt"
    $git add -A
    $git commit -m "For mixed reset" > /dev/null 2>&1
    $git reset HEAD~1 > "$RESULTS_DIR/reset_mixed_$label.txt" 2>&1
    $git status --porcelain > "$RESULTS_DIR/reset_mixed_status_$label.txt" 2>&1

    # Cleanup
    $git checkout -- .
    $git clean -fd > /dev/null 2>&1
}

# Test: cherry-pick operations
test_cherrypick() {
    local git="$1"
    local label="$2"

    log "[$label] Testing cherry-pick operations..."

    cd "$TEST_DIR"

    # Create a branch with commits to cherry-pick
    $git checkout -b "cherrypick-source-$label" > /dev/null 2>&1

    for i in $(seq 1 3); do
        echo "Cherry-pick content $i" > "cherry_$i.txt"
        $git add -A
        $git commit -m "Cherry-pick source $i" > /dev/null 2>&1
    done

    # Get commit hashes
    commits=$($git log --oneline -3 --format="%H")

    # Go to main and cherry-pick
    $git checkout main > /dev/null 2>&1 || $git checkout master > /dev/null 2>&1

    for commit in $commits; do
        $git cherry-pick "$commit" > "$RESULTS_DIR/cherrypick_$label.txt" 2>&1 || true
    done
}

# Test: fsck and gc operations
test_maintenance() {
    local git="$1"
    local label="$2"

    log "[$label] Testing maintenance operations..."

    cd "$TEST_DIR"

    $git fsck > "$RESULTS_DIR/fsck_$label.txt" 2>&1
    $git gc --quiet > "$RESULTS_DIR/gc_$label.txt" 2>&1
    $git count-objects -v > "$RESULTS_DIR/count_objects_$label.txt" 2>&1
}

# Test: rev-parse and show-ref
test_refs() {
    local git="$1"
    local label="$2"

    log "[$label] Testing ref operations..."

    cd "$TEST_DIR"

    $git rev-parse HEAD > "$RESULTS_DIR/revparse_head_$label.txt" 2>&1
    $git rev-parse --abbrev-ref HEAD > "$RESULTS_DIR/revparse_abbrev_$label.txt" 2>&1
    $git show-ref > "$RESULTS_DIR/showref_$label.txt" 2>&1
    $git for-each-ref > "$RESULTS_DIR/foreachref_$label.txt" 2>&1
}

# Test: ls-files and ls-tree
test_ls() {
    local git="$1"
    local label="$2"

    log "[$label] Testing ls operations..."

    cd "$TEST_DIR"

    $git ls-files > "$RESULTS_DIR/lsfiles_$label.txt" 2>&1
    $git ls-files --stage > "$RESULTS_DIR/lsfiles_stage_$label.txt" 2>&1
    $git ls-tree -r HEAD > "$RESULTS_DIR/lstree_$label.txt" 2>&1
    $git ls-tree --name-only -r HEAD > "$RESULTS_DIR/lstree_names_$label.txt" 2>&1
}

# Test: grep operations
test_grep() {
    local git="$1"
    local label="$2"

    log "[$label] Testing grep operations..."

    cd "$TEST_DIR"

    $git grep "content" > "$RESULTS_DIR/grep_content_$label.txt" 2>&1 || true
    $git grep -c "content" > "$RESULTS_DIR/grep_count_$label.txt" 2>&1 || true
    $git grep -l "line" > "$RESULTS_DIR/grep_files_$label.txt" 2>&1 || true
}

# Run rapid file operations to stress fsmonitor
test_rapid_changes() {
    local git="$1"
    local label="$2"

    log "[$label] Testing rapid file changes..."

    cd "$TEST_DIR"

    # Rapidly create, modify, and delete files while checking status
    for i in $(seq 1 100); do
        echo "Rapid $i" > "rapid_$i.txt"
        $git status --porcelain > /dev/null 2>&1
    done

    $git add -A
    $git commit -m "Rapid changes" > /dev/null 2>&1

    for i in $(seq 1 100); do
        rm -f "rapid_$i.txt"
        $git status --porcelain > /dev/null 2>&1
    done

    $git add -A
    $git commit -m "Remove rapid files" > /dev/null 2>&1

    $git status --porcelain > "$RESULTS_DIR/rapid_status_$label.txt" 2>&1
}

# Test directory rename operations (important for inotify)
test_directory_renames() {
    local git="$1"
    local label="$2"

    log "[$label] Testing directory renames..."

    cd "$TEST_DIR"

    # Create a directory with files
    mkdir -p "rename_test_dir"
    for i in $(seq 1 20); do
        echo "Rename test $i" > "rename_test_dir/file_$i.txt"
    done

    $git add -A
    $git commit -m "Add rename test dir" > /dev/null 2>&1

    # Rename the directory
    mv "rename_test_dir" "renamed_dir"
    $git status --porcelain > "$RESULTS_DIR/dirrename_status_$label.txt" 2>&1

    $git add -A
    $git commit -m "Renamed directory" > /dev/null 2>&1
}

# Test nested directory operations
test_nested_dirs() {
    local git="$1"
    local label="$2"

    log "[$label] Testing nested directory operations..."

    cd "$TEST_DIR"

    # Create deeply nested directories
    mkdir -p "level1/level2/level3/level4/level5"
    for i in $(seq 1 5); do
        echo "Level $i" > "level1/level2/level3/level4/level5/file_$i.txt"
    done

    $git add -A
    $git commit -m "Nested dirs" > /dev/null 2>&1

    # Modify files at various levels
    echo "Modified" >> "level1/level2/level3/level4/level5/file_1.txt"
    echo "New file" > "level1/level2/new_file.txt"

    $git status --porcelain > "$RESULTS_DIR/nested_status_$label.txt" 2>&1
    $git diff --stat > "$RESULTS_DIR/nested_diff_$label.txt" 2>&1

    $git add -A
    $git commit -m "Nested modifications" > /dev/null 2>&1
}

# Compare result files
compare_results() {
    log "Comparing results between baseline and fsmonitor..."

    local differences=0
    local compared=0

    echo "" > "$RESULTS_DIR/comparison_report.txt"
    echo "=== FSMonitor Stress Test Comparison Report ===" >> "$RESULTS_DIR/comparison_report.txt"
    echo "Date: $(date)" >> "$RESULTS_DIR/comparison_report.txt"
    echo "" >> "$RESULTS_DIR/comparison_report.txt"

    for baseline_file in "$RESULTS_DIR"/*_baseline.txt; do
        if [ -f "$baseline_file" ]; then
            fsmon_file="${baseline_file/_baseline.txt/_fsmonitor.txt}"
            test_name=$(basename "$baseline_file" "_baseline.txt")

            if [ -f "$fsmon_file" ]; then
                compared=$((compared + 1))

                if diff -q "$baseline_file" "$fsmon_file" > /dev/null 2>&1; then
                    echo "[PASS] $test_name" >> "$RESULTS_DIR/comparison_report.txt"
                else
                    differences=$((differences + 1))
                    echo "[DIFF] $test_name" >> "$RESULTS_DIR/comparison_report.txt"
                    echo "  --- Differences ---" >> "$RESULTS_DIR/comparison_report.txt"
                    diff "$baseline_file" "$fsmon_file" >> "$RESULTS_DIR/comparison_report.txt" 2>&1 || true
                    echo "" >> "$RESULTS_DIR/comparison_report.txt"
                fi
            fi
        fi
    done

    echo "" >> "$RESULTS_DIR/comparison_report.txt"
    echo "=== Summary ===" >> "$RESULTS_DIR/comparison_report.txt"
    echo "Tests compared: $compared" >> "$RESULTS_DIR/comparison_report.txt"
    echo "Differences found: $differences" >> "$RESULTS_DIR/comparison_report.txt"

    if [ $differences -eq 0 ]; then
        echo -e "${GREEN}All tests passed - no semantic differences detected!${NC}"
    else
        echo -e "${RED}Found $differences differences out of $compared comparisons${NC}"
    fi

    return $differences
}

# Main test execution
main() {
    log "Starting FSMonitor stress test..."
    log "Baseline git: $BASELINE_GIT"
    log "FSMonitor git: $FSMONITOR_GIT"

    # Verify binaries exist
    if [ ! -x "$BASELINE_GIT" ]; then
        error "Baseline git not found: $BASELINE_GIT"
        exit 1
    fi

    if [ ! -x "$FSMONITOR_GIT" ]; then
        error "FSMonitor git not found: $FSMONITOR_GIT"
        exit 1
    fi

    # Clear results
    rm -rf "$RESULTS_DIR"/*

    # Run tests with BASELINE git
    log "=========================================="
    log "Running tests with BASELINE git (no fsmonitor backend)"
    log "=========================================="

    create_test_repo "$BASELINE_GIT"
    test_status "$BASELINE_GIT" "baseline"
    test_diff "$BASELINE_GIT" "baseline"
    test_commits "$BASELINE_GIT" "baseline"
    test_branches "$BASELINE_GIT" "baseline"
    test_merges "$BASELINE_GIT" "baseline"
    test_stash "$BASELINE_GIT" "baseline"
    test_refs "$BASELINE_GIT" "baseline"
    test_ls "$BASELINE_GIT" "baseline"
    test_grep "$BASELINE_GIT" "baseline"
    test_rapid_changes "$BASELINE_GIT" "baseline"
    test_directory_renames "$BASELINE_GIT" "baseline"
    test_nested_dirs "$BASELINE_GIT" "baseline"
    test_maintenance "$BASELINE_GIT" "baseline"

    # Run tests with FSMONITOR git
    log "=========================================="
    log "Running tests with FSMONITOR git"
    log "=========================================="

    create_test_repo "$FSMONITOR_GIT"
    test_status "$FSMONITOR_GIT" "fsmonitor"
    test_diff "$FSMONITOR_GIT" "fsmonitor"
    test_commits "$FSMONITOR_GIT" "fsmonitor"
    test_branches "$FSMONITOR_GIT" "fsmonitor"
    test_merges "$FSMONITOR_GIT" "fsmonitor"
    test_stash "$FSMONITOR_GIT" "fsmonitor"
    test_refs "$FSMONITOR_GIT" "fsmonitor"
    test_ls "$FSMONITOR_GIT" "fsmonitor"
    test_grep "$FSMONITOR_GIT" "fsmonitor"
    test_rapid_changes "$FSMONITOR_GIT" "fsmonitor"
    test_directory_renames "$FSMONITOR_GIT" "fsmonitor"
    test_nested_dirs "$FSMONITOR_GIT" "fsmonitor"
    test_maintenance "$FSMONITOR_GIT" "fsmonitor"

    # Compare results
    log "=========================================="
    log "Comparing results..."
    log "=========================================="
    compare_results

    log "Results saved to: $RESULTS_DIR"
    log "Test completed!"
}

# Run specific test with fsmonitor daemon enabled
test_with_daemon() {
    local git="$1"
    local label="$2"

    log "[$label] Testing with fsmonitor daemon..."

    cd "$TEST_DIR"

    # Enable fsmonitor
    $git config core.fsmonitor true 2>/dev/null || true

    # Start the daemon (if supported)
    $git fsmonitor--daemon start > "$RESULTS_DIR/daemon_start_$label.txt" 2>&1 || true

    # Run some operations
    $git status --porcelain > "$RESULTS_DIR/daemon_status_$label.txt" 2>&1

    # Make changes
    for i in $(seq 1 50); do
        echo "Daemon test $i" > "daemon_test_$i.txt"
    done

    sleep 1  # Give daemon time to notice changes

    $git status --porcelain > "$RESULTS_DIR/daemon_status2_$label.txt" 2>&1

    # Stop daemon
    $git fsmonitor--daemon stop > "$RESULTS_DIR/daemon_stop_$label.txt" 2>&1 || true

    # Disable fsmonitor
    $git config --unset core.fsmonitor 2>/dev/null || true

    # Cleanup
    $git checkout -- . 2>/dev/null || true
    rm -f daemon_test_*.txt 2>/dev/null || true
}

main "$@"
