# z.fish - fish port of z.sh

# Set up default values if not already set
set -q _Z_CMD; or set -gx _Z_CMD "z"
set -q _Z_DATA; or set -gx _Z_DATA "$HOME/.z"
set -q _Z_MAX_SCORE; or set -gx _Z_MAX_SCORE 9000

# Check if datafile is a directory
if test -d $_Z_DATA
    echo "ERROR: z.fish's datafile ($_Z_DATA) is a directory."
end

function _z -d "Jump to a recent directory."
    set -f datafile "$_Z_DATA"

    # Handle symlinks
    if test -L "$datafile"
        set datafile (readlink "$datafile")
    end

    # Bail if we don't own datafile and $_Z_OWNER not set
    if test -z "$_Z_OWNER"; and test -f "$datafile"; and not test (id -u) = (stat -f %u "$datafile")
        return
    end

    function _z_dirs
        test -f "$argv"; or return
        while read -l line
            set -l dir (string split '|' $line)[1]
            if test -d "$dir"
                echo $line
            end
        end < "$argv"
    end

    # Add entry
    if test "$argv[1]" = "--add"
        set -e argv[1]
        set -l dir $argv

        # Skip if it's $HOME or root
        if test "$dir" = "$HOME" -o "$dir" = "/"
            return
        end

        # Check excluded directories
        if set -q _Z_EXCLUDE_DIRS
            for exclude in $_Z_EXCLUDE_DIRS
                if string match -q "$exclude*" -- $dir
                    return
                end
            end
        end

        # Add entry to datafile
        set -l tempfile "$datafile.$RANDOM"

        _z_dirs $datafile | awk -v path="$dir" -v now=(date +%s) -v score=$_Z_MAX_SCORE -F"|" '
            BEGIN {
                rank[path] = 1
                time[path] = now
            }
            $2 >= 1 {
                # drop ranks below 1
                if( $1 == path ) {
                    rank[$1] = $2 + 1
                    time[$1] = now
                } else {
                    rank[$1] = $2
                    time[$1] = $3
                }
                count += $2
            }
            END {
                if( count > score ) {
                    # aging
                    for( x in rank ) print x "|" 0.99*rank[x] "|" time[x]
                } else for( x in rank ) print x "|" rank[x] "|" time[x]
            }
        ' 2>/dev/null >$tempfile

        if test $status -eq 0
            if test -n "$_Z_OWNER"
                chown $_Z_OWNER:"$(id -ng $_Z_OWNER)" "$tempfile"
            end
            mv -f "$tempfile" "$datafile"
        else
            rm -f "$tempfile"
        end

    # Complete
    else if test "$argv[1]" = "--complete"
        if test -f "$datafile"
            while read -l line
                set -l dir (string split '|' $line)[1]
                if test -d "$dir"
                    echo $dir
                end
            end < "$datafile"
        end

    # List/Search
    else
        set -l typ
        set -l list
        set -l echo
        set -l fnd

        # Parse options
        set -l options "h/help" "l/list" "r/rank" "t/recent" "e/echo" "c/current" "x/delete"
        argparse $options -- $argv

        if set -q _flag_help
            echo "Usage: $_Z_CMD [-cehlrtx] args..." >&2
            return
        end

        set -q _flag_list; and set list 1
        set -q _flag_rank; and set typ "rank"
        set -q _flag_recent; and set typ "recent"

        if set -q _flag_current
            set fnd "^$PWD $fnd"
        end

        if set -q _flag_delete
            sed -i -e "\:^$PWD|.*:d" "$datafile"
            return
        end

        # Build search string from remaining arguments
        for arg in $argv
            set fnd "$fnd $arg"
        end
        set fnd (string trim "$fnd")

        [ -f "$datafile" ]; or return

        if test -n "$argv[1]"
            if test -d "$argv[1]"
                if test -z "$list"
                    cd "$argv[1]"
                    return
                end
            end
        end

        set -l result (_z_dirs $datafile | awk -v t=(date +%s) -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
            function frecent(rank, time) {
              # relate frequency and time
                dx = t - time
              return int(10000 _rank_ (3.75/((0.0001 * dx + 1) + 0.25)))
            }
            function output(matches, best_match, common) {
                # list or return the desired directory
                if( list ) {
                    if( common ) {
                        printf "%-10s %s\n", "common:", common > "/dev/stderr"
                    }
                    cmd = "sort -n >&2"
                    for( x in matches ) {
                        if( matches[x] ) {
                            printf "%-10s %s\n", matches[x], x | cmd
                        }
                    }
                } else {
                    if( common && !typ ) best_match = common
                    print best_match
                }
            }
            function common(matches) {
                # find the common root of a list of matches, if it exists
                for( x in matches ) {
                    if( matches[x] && (!short || length(x) < length(short)) ) {
                        short = x
                    }
                }
                if( short == "/" ) return
                for( x in matches ) if( matches[x] && index(x, short) != 1 ) {
                    return
                }
                return short
            }
            BEGIN {
                gsub(" ", ".*", q)
                hi_rank = ihi_rank = -9999999999
            }
            {
                if( typ == "rank" ) {
                    rank = $2
                } else if( typ == "recent" ) {
                    rank = $3 - t
                } else rank = frecent($2, $3)
                if( $1 ~ q ) {
                    matches[$1] = rank
                } else if( tolower($1) ~ tolower(q) ) imatches[$1] = rank
                if( matches[$1] && matches[$1] > hi_rank ) {
                    best_match = $1
                    hi_rank = matches[$1]
                } else if( imatches[$1] && imatches[$1] > ihi_rank ) {
                    ibest_match = $1
                    ihi_rank = imatches[$1]
                }
            }
            END {
                # prefer case sensitive
                if( best_match ) {
                    output(matches, best_match, common(matches))
                    exit
                } else if( ibest_match ) {
                    output(imatches, ibest_match, common(imatches))
                    exit
                }
                exit(1)
            }
        ')

        if test $status -eq 0; and test -n "$result"
            if set -q _flag_echo
                echo "$result"
            else if test -d "$result"
                cd "$result"
            end
        else
            return $status
        end
    end
end

# Wrapper function that enables the behavior to change directory
function z -d "jump to directory"
    _z $argv
end

# Register completions
complete -c $_Z_CMD -a "(_z --complete (commandline -t))"

# Add directory on directory change
function _z_on_pwd --on-variable PWD
    status --is-command-substitution; and return
    _z --add "$PWD" &
end
