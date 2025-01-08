# z.fish

Generated from https://github.com/rupa/z/blob/master/z.sh using the following conversation and some debugging.

### USER
I’m trying to port z.sh to the fish shell.  Here’s the Bash source, can you rewrite it in fish for me please?

```  
# Copyright (c) 2009 rupa deadwyler. Licensed under the WTFPL license, Version 2
# maintains a jump-list of the directories you actually use
#
# INSTALL:
#     * put something like this in your .bashrc/.zshrc:
#         . /path/to/z.sh
#     * cd around for a while to build up the db
#     * PROFIT!!
#     * optionally:
#         set $_Z_CMD in .bashrc/.zshrc to change the command (default z).
#         set $_Z_DATA in .bashrc/.zshrc to change the datafile (default ~/.z).
#         set $_Z_MAX_SCORE lower to age entries out faster (default 9000).
#         set $_Z_NO_RESOLVE_SYMLINKS to prevent symlink resolution.
#         set $_Z_NO_PROMPT_COMMAND if you're handling PROMPT_COMMAND yourself.
#         set $_Z_EXCLUDE_DIRS to an array of directories to exclude.
#         set $_Z_OWNER to your username if you want use z while sudo with $HOME kept
#
# USE:
#     * z foo     # cd to most frecent dir matching foo
#     * z foo bar # cd to most frecent dir matching foo and bar
#     * z -r foo  # cd to highest ranked dir matching foo
#     * z -t foo  # cd to most recently accessed dir matching foo
#     * z -l foo  # list matches instead of cd
#     * z -e foo  # echo the best match, don't cd
#     * z -c foo  # restrict matches to subdirs of $PWD
#     * z -x      # remove the current directory from the datafile
#     * z -h      # show a brief help message
[ -d "${_Z_DATA:-$HOME/.z}" ] && {
    echo "ERROR: z.sh's datafile (${_Z_DATA:-$HOME/.z}) is a directory."
}
_z() {
    local datafile="${_Z_DATA:-$HOME/.z}"
    # if symlink, dereference
    [ -h "$datafile" ] && datafile=$(readlink "$datafile")
    # bail if we don't own ~/.z and $_Z_OWNER not set
    [ -z "$_Z_OWNER" -a -f "$datafile" -a ! -O "$datafile" ] && return
    _z_dirs () {
        [ -f "$datafile" ] || return
        local line
        while read line; do
            # only count directories
            [ -d "${line%%\|*}" ] && echo "$line"
        done < "$datafile"
        return 0
    }
    # add entries
    if [ "$1" = "--add" ]; then
        shift
        # $HOME and / aren't worth matching
        [ "$*" = "$HOME" -o "$*" = '/' ] && return
        # don't track excluded directory trees
        if [ ${#_Z_EXCLUDE_DIRS[@]} -gt 0 ]; then
            local exclude
            for exclude in "${_Z_EXCLUDE_DIRS[@]}"; do
                case "$*" in "$exclude"*) return;; esac
            done
        fi
        # maintain the data file
        local tempfile="$datafile.$RANDOM"
        local score=${_Z_MAX_SCORE:-9000}
        _z_dirs | \awk -v path="$*" -v now="$(\date +%s)" -v score=$score -F"|" '
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
        ' 2>/dev/null >| "$tempfile"
        # do our best to avoid clobbering the datafile in a race condition.
        if [ $? -ne 0 -a -f "$datafile" ]; then
            \env rm -f "$tempfile"
        else
            [ "$_Z_OWNER" ] && chown $_Z_OWNER:"$(id -ng $_Z_OWNER)" "$tempfile"
            \env mv -f "$tempfile" "$datafile" || \env rm -f "$tempfile"
        fi
    # tab completion
    elif [ "$1" = "--complete" -a -s "$datafile" ]; then
        _z_dirs | \awk -v q="$2" -F"|" '
            BEGIN {
                q = substr(q, 3)
                if( q == tolower(q) ) imatch = 1
                gsub(/ /, ".*", q)
            }
            {
                if( imatch ) {
                    if( tolower($1) ~ q ) print $1
                } else if( $1 ~ q ) print $1
            }
        ' 2>/dev/null
    else
        # list/go
        local echo fnd last list opt typ
        while [ "$1" ]; do case "$1" in
            --) while [ "$1" ]; do shift; fnd="$fnd${fnd:+ }$1";done;;
            -*) opt=${1:1}; while [ "$opt" ]; do case ${opt:0:1} in
                    c) fnd="^$PWD $fnd";;
                    e) echo=1;;
                    h) echo "${_Z_CMD:-z} [-cehlrtx] args" >&2; return;;
                    l) list=1;;
                    r) typ="rank";;
                    t) typ="recent";;
                    x) \sed -i -e "\:^${PWD}|.*:d" "$datafile";;
                esac; opt=${opt:1}; done;;
             *) fnd="$fnd${fnd:+ }$1";;
        esac; last=$1; [ "$#" -gt 0 ] && shift; done
        [ "$fnd" -a "$fnd" != "^$PWD " ] || list=1
        # if we hit enter on a completion just go there
        case "$last" in
            # completions will always start with /
            /*) [ -z "$list" -a -d "$last" ] && builtin cd "$last" && return;;
        esac
        # no file yet
        [ -f "$datafile" ] || return
        local cd
        cd="$( < <( _z_dirs ) \awk -v t="$(\date +%s)" -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
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
        ')"
        if [ "$?" -eq 0 ]; then
          if [ "$cd" ]; then
            if [ "$echo" ]; then echo "$cd"; else builtin cd "$cd"; fi
          fi
        else
          return $?
        fi
    fi
}
alias ${_Z_CMD:-z}='_z 2>&1'
[ "$_Z_NO_RESOLVE_SYMLINKS" ] || _Z_RESOLVE_SYMLINKS="-P"
if type compctl >/dev/null 2>&1; then
    # zsh
    [ "$_Z_NO_PROMPT_COMMAND" ] || {
        # populate directory list, avoid clobbering any other precmds.
        if [ "$_Z_NO_RESOLVE_SYMLINKS" ]; then
            _z_precmd() {
                (_z --add "${PWD:a}" &)
                : $RANDOM
            }
        else
            _z_precmd() {
                (_z --add "${PWD:A}" &)
                : $RANDOM
            }
        fi
        [[ -n "${precmd_functions[(r)_z_precmd]}" ]] || {
            precmd_functions[$(($#precmd_functions+1))]=_z_precmd
        }
    }
    _z_zsh_tab_completion() {
        # tab completion
        local compl
        read -l compl
        reply=(${(f)"$(_z --complete "$compl")"})
    }
    compctl -U -K _z_zsh_tab_completion _z
elif type complete >/dev/null 2>&1; then
    # bash
    # tab completion
    complete -o filenames -C '_z --complete "$COMP_LINE"' ${_Z_CMD:-z}
    [ "$_Z_NO_PROMPT_COMMAND" ] || {
        # populate directory list. avoid clobbering other PROMPT_COMMANDs.
        grep "_z --add" <<< "$PROMPT_COMMAND" >/dev/null || {
            PROMPT_COMMAND="$PROMPT_COMMAND"$'\n''(_z --add "$(command pwd '$_Z_RESOLVE_SYMLINKS' 2>/dev/null)" 2>/dev/null &);'
        }
    }
fi  
```

### ASSISTANT
Here's a Fish shell port of z.sh. Note that this is a complex script and you'll want to test it thoroughly:

```fish
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
    set -l datafile "$_Z_DATA"

    # Handle symlinks
    if test -L "$datafile"
        set datafile (readlink "$datafile")
    end

    # Bail if we don't own datafile and $_Z_OWNER not set
    if test -z "$_Z_OWNER"; and test -f "$datafile"; and not test (id -u) = (stat -f %u "$datafile")
        return
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
        
        if test -f "$datafile"
            awk -v path="$dir" -v now=(date +%s) -v score=$_Z_MAX_SCORE -F"|" '
                BEGIN {
                    rank[path] = 1
                    time[path] = now
                }
                $2 >= 1 {
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
                        for( x in rank ) print x "|" 0.99*rank[x] "|" time[x]
                    } else for( x in rank ) print x "|" rank[x] "|" time[x]
                }
            ' "$datafile" 2>/dev/null >$tempfile
            
            if test $status -eq 0
                mv -f "$tempfile" "$datafile"
            else
                rm -f "$tempfile"
            end
        else
            echo "$dir|1|"(date +%s) >$datafile
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
        set -q _flag_echo; and set echo 1
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

        set -l cd (while read -l line
            set -l parts (string split '|' $line)
            set -l dir $parts[1]
            set -l rank $parts[2]
            set -l time $parts[3]

            if test -d $dir
                if string match -q -- "*$fnd*" $dir
                    echo "$rank|$time|$dir"
                end
            end
        end < "$datafile" | sort -n -r | head -n 1 | cut -d'|' -f3)

        if test -n "$cd"
            if test -n "$echo"
                echo "$cd"
            else
                cd "$cd"
            end
        end
    end
end

# Register completions
complete -c $_Z_CMD -a "(_z --complete (commandline -t))"

# Add directory on directory change
function _z_on_pwd --on-variable PWD
    status --is-command-substitution; and return
    _z --add "$PWD" &
end
```

This port maintains most of the functionality of the original z.sh, but adapted for Fish's syntax and conventions. Key changes include:

1. Uses Fish's native argument parsing
2. Implements Fish-style completions
3. Uses Fish's event system for tracking directory changes
4. Maintains compatibility with the same data file format

To use it:

1. Save it as `~/.config/fish/functions/z.fish`
2. Restart your shell or source the file
3. Start using it with the same commands as z.sh:
    - `z foo` to cd to most frecent dir matching foo
    - `z -r foo` for highest ranked match
    - `z -t foo` for most recent match
    - `z -l foo` to list matches
    - etc.

Note that some advanced features might need additional testing and refinement. You may need to adjust paths and permissions according to your setup.

### USER
How do I actually set the `z` alias for `_z`?

### ASSISTANT
In Fish, you can create the alias in a few ways:

1. Add this line to the z.fish file:
```fish
alias z='_z'
```

2. Or more idiomatically for Fish, create a function called `z.fish` in `~/.config/fish/functions/`:
```fish
function z
    _z $argv
end
```

The function approach is generally preferred in Fish since it provides better handling of arguments and integrates better with Fish's autoloading system.

You can also set the alias immediately in your terminal by running either command above. I'd recommend the function approach since it's more consistent with Fish's design philosophy.

The advantage of putting it in a separate function file is that Fish will autoload it when needed, which is more efficient than loading it with your shell startup.

### USER
Can you change the file to use the awk script for working out the “frecent” result?

### ASSISTANT
Here's the modified version using the original awk script for frecency calculations:

```fish
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
    set -l datafile "$_Z_DATA"

    # Handle symlinks
    if test -L "$datafile"
        set datafile (readlink "$datafile")
    end

    # Bail if we don't own datafile and $_Z_OWNER not set
    if test -z "$_Z_OWNER"; and test -f "$datafile"; and not test (id -u) = (stat -f %u "$datafile")
        return
    end

    function _z_dirs
        [ -f "$datafile" ]; or return
        while read -l line
            set -l dir (string split '|' $line)[1]
            if test -d "$dir"
                echo $line
            end
        end < "$datafile"
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
        
        _z_dirs | awk -v path="$dir" -v now=(date +%s) -v score=$_Z_MAX_SCORE -F"|" '
            BEGIN {
                rank[path] = 1
                time[path] = now
            }
            $2 >= 1 {
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
        _z_dirs | awk -v q="$argv[2]" -F"|" '
            BEGIN {
                q = substr(q, 3)
                if( q == tolower(q) ) imatch = 1
                gsub(/ /, ".*", q)
            }
            {
                if( imatch ) {
                    if( tolower($1) ~ q ) print $1
                } else if( $1 ~ q ) print $1
            }
        ' 2>/dev/null

    # List/Search
    else
        set -l typ
        set -l list
        set -l echo
        set -l fnd
        set -l last

        # Parse arguments
        while test (count $argv) -gt 0
            switch $argv[1]
                case '--'
                    set -e argv[1]
                    set fnd (string join ' ' $argv)
                    break
                case '-*'
                    set -l opt (string sub -s 2 $argv[1])
                    while test -n "$opt"
                        switch (string sub -s 1 -l 1 $opt)
                            case 'c'
                                set fnd "^$PWD $fnd"
                            case 'e'
                                set echo 1
                            case 'h'
                                echo "$_Z_CMD [-cehlrtx] args" >&2
                                return
                            case 'l'
                                set list 1
                            case 'r'
                                set typ "rank"
                            case 't'
                                set typ "recent"
                            case 'x'
                                sed -i -e "\:^$PWD|.*:d" "$datafile"
                                return
                        end
                        set opt (string sub -s 2 $opt)
                    end
                case '*'
                    set fnd "$fnd $argv[1]"
            end
            set last $argv[1]
            set -e argv[1]
        end

        [ -f "$datafile" ]; or return
        
        set -l cd (_z_dirs | awk -v t=(date +%s) -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
            function frecent(rank, time) {
                dx = t - time
                return int(10000 * rank * (3.75/((0.0001 * dx + 1) + 0.25)))
            }
            function output(matches, best_match, common) {
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

        if test $status -eq 0; and test -n "$cd"
            if test -n "$echo"
                echo "$cd"
            else
                cd "$cd"
            end
        end
    end
end

# Register completions
complete -c $_Z_CMD -a "(_z --complete (commandline -t))"

# Add directory on directory change
function _z_on_pwd --on-variable PWD
    status --is-command-substitution; and return
    _z --add "$PWD" &
end
```

The main changes are:

1. Added the `_z_dirs` helper function to handle directory filtering
2. Restored the original awk script for frecency calculation and matching
3. Maintained the same ranking algorithm from the original z.sh

This version should now provide results that are more consistent with the original z.sh implementation.

Don't forget to create the `z` function as mentioned in the previous response:

```fish
function z
    _z $argv
end
```

This version should provide identical ranking and matching behavior to the original z.sh.

### USER
Your first version worked, but with poor frecency.  Your second version looks like it’s got better frecency, but doesn’t actually change the directory.  Can you fix it?

### ASSISTANT
Here's the fixed version that combines both working directory changes and proper frecency:

```fish
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
    set -l datafile "$_Z_DATA"

    # Handle symlinks
    if test -L "$datafile"
        set datafile (readlink "$datafile")
    end

    # Bail if we don't own datafile and $_Z_OWNER not set
    if test -z "$_Z_OWNER"; and test -f "$datafile"; and not test (id -u) = (stat -f %u "$datafile")
        return
    end

    function _z_dirs
        [ -f "$datafile" ]; or return
        while read -l line
            set -l dir (string split '|' $line)[1]
            if test -d "$dir"
                echo $line
            end
        end < "$datafile"
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
        
        _z_dirs | awk -v path="$dir" -v now=(date +%s) -v score=$_Z_MAX_SCORE -F"|" '
            BEGIN {
                rank[path] = 1
                time[path] = now
            }
            $2 >= 1 {
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
        _z_dirs | awk -v q="$argv[2]" -F"|" '
            BEGIN {
                q = substr(q, 3)
                if( q == tolower(q) ) imatch = 1
                gsub(/ /, ".*", q)
            }
            {
                if( imatch ) {
                    if( tolower($1) ~ q ) print $1
                } else if( $1 ~ q ) print $1
            }
        ' 2>/dev/null

    # List/Search
    else
        set -l typ
        set -l list
        set -l echo
        set -l fnd
        set -l last

        # Parse arguments
        while test (count $argv) -gt 0
            switch $argv[1]
                case '--'
                    set -e argv[1]
                    set fnd (string join ' ' $argv)
                    break
                case '-*'
                    set -l opt (string sub -s 2 $argv[1])
                    while test -n "$opt"
                        switch (string sub -s 1 -l 1 $opt)
                            case 'c'
                                set fnd "^$PWD $fnd"
                            case 'e'
                                set echo 1
                            case 'h'
                                echo "$_Z_CMD [-cehlrtx] args" >&2
                                return
                            case 'l'
                                set list 1
                            case 'r'
                                set typ "rank"
                            case 't'
                                set typ "recent"
                            case 'x'
                                sed -i -e "\:^$PWD|.*:d" "$datafile"
                                return
                        end
                        set opt (string sub -s 2 $opt)
                    end
                case '*'
                    set fnd "$fnd $argv[1]"
            end
            set last $argv[1]
            set -e argv[1]
        end

        [ -f "$datafile" ]; or return

        if test -n "$last"
            if test -d "$last"
                if test -z "$list"
                    cd "$last"
                    return
                end
            end
        end
        
        set -l result (_z_dirs | awk -v t=(date +%s) -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
            function frecent(rank, time) {
                dx = t - time
                return int(10000 * rank * (3.75/((0.0001 * dx + 1) + 0.25)))
            }
            function output(matches, best_match, common) {
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
            if test -n "$echo"
                echo "$result"
            else if test -d "$result"
                cd "$result"
            end
        end
    end
end

# Register completions
complete -c $_Z_CMD -a "(_z --complete (commandline -t))"

# Add directory on directory change
function _z_on_pwd --on-variable PWD
    status --is-command-substitution; and return
    _z --add "$PWD" &
end
```

The key fixes are:

1. Properly capturing and handling the awk output with `set -l result`
2. Adding an explicit check for directory existence before changing to it
3. Making sure the cd command actually executes with the result

You'll still need the wrapper function:

```fish
function z
    _z $argv
end
```

This version should now both use the proper frecency algorithm AND successfully change directories.

### USER
Can you restore the fish native argument parsing, please?  And include the wrapper in the file.

### ASSISTANT
Here's the combined version with Fish's argparse restored:

```fish
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
    set -l datafile "$_Z_DATA"

    # Handle symlinks
    if test -L "$datafile"
        set datafile (readlink "$datafile")
    end

    # Bail if we don't own datafile and $_Z_OWNER not set
    if test -z "$_Z_OWNER"; and test -f "$datafile"; and not test (id -u) = (stat -f %u "$datafile")
        return
    end

    function _z_dirs
        [ -f "$datafile" ]; or return
        while read -l line
            set -l dir (string split '|' $line)[1]
            if test -d "$dir"
                echo $line
            end
        end < "$datafile"
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
        
        _z_dirs | awk -v path="$dir" -v now=(date +%s) -v score=$_Z_MAX_SCORE -F"|" '
            BEGIN {
                rank[path] = 1
                time[path] = now
            }
            $2 >= 1 {
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
        _z_dirs | awk -v q="$argv[2]" -F"|" '
            BEGIN {
                q = substr(q, 3)
                if( q == tolower(q) ) imatch = 1
                gsub(/ /, ".*", q)
            }
            {
                if( imatch ) {
                    if( tolower($1) ~ q ) print $1
                } else if( $1 ~ q ) print $1
            }
        ' 2>/dev/null

    # List/Search
    else
        # Parse options
        set -l options "h/help" "l/list" "r/rank" "t/recent" "e/echo" "c/current" "x/delete"
        argparse $options -- $argv
        or return

        if set -q _flag_help
            echo "Usage: $_Z_CMD [-cehlrtx] args..." >&2
            return
        end

        set -l typ
        set -l list
        set -l echo
        set -l fnd (string join ' ' $argv)

        if set -q _flag_list
            set list 1
        end
        if set -q _flag_echo
            set echo 1
        end
        if set -q _flag_rank
            set typ "rank"
        end
        if set -q _flag_recent
            set typ "recent"
        end
        if set -q _flag_current
            set fnd "^$PWD $fnd"
        end
        if set -q _flag_delete
            sed -i -e "\:^$PWD|.*:d" "$datafile"
            return
        end

        [ -f "$datafile" ]; or return

        if test -n "$argv[1]"
            if test -d "$argv[1]"
                if test -z "$list"
                    cd "$argv[1]"
                    return
                end
            end
        end
        
        set -l result (_z_dirs | awk -v t=(date +%s) -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
            function frecent(rank, time) {
                dx = t - time
                return int(10000 * rank * (3.75/((0.0001 * dx + 1) + 0.25)))
            }
            function output(matches, best_match, common) {
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
            if test -n "$echo"
                echo "$result"
            else if test -d "$result"
                cd "$result"
            end
        end
    end
end

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
```

The main changes are:
1. Restored Fish's `argparse` for option handling
2. Included the `z` wrapper function in the same file
3. Simplified the argument handling using Fish's native option parsing

This should now give you the best of both worlds: Fish's clean argument parsing and the original z.sh's frecency algorithm.

### USER
That seems to update the data file, but doesn’t actually change directory when I run it.

### ASSISTANT
Here's the fixed version with the directory change working:

```fish
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
    set -l datafile "$_Z_DATA"

    # Handle symlinks
    if test -L "$datafile"
        set datafile (readlink "$datafile")
    end

    # Bail if we don't own datafile and $_Z_OWNER not set
    if test -z "$_Z_OWNER"; and test -f "$datafile"; and not test (id -u) = (stat -f %u "$datafile")
        return
    end

    function _z_dirs
        [ -f "$datafile" ]; or return
        while read -l line
            set -l dir (string split '|' $line)[1]
            if test -d "$dir"
                echo $line
            end
        end < "$datafile"
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
        
        _z_dirs | awk -v path="$dir" -v now=(date +%s) -v score=$_Z_MAX_SCORE -F"|" '
            BEGIN {
                rank[path] = 1
                time[path] = now
            }
            $2 >= 1 {
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
        _z_dirs | awk -v q="$argv[2]" -F"|" '
            BEGIN {
                q = substr(q, 3)
                if( q == tolower(q) ) imatch = 1
                gsub(/ /, ".*", q)
            }
            {
                if( imatch ) {
                    if( tolower($1) ~ q ) print $1
                } else if( $1 ~ q ) print $1
            }
        ' 2>/dev/null

    # List/Search
    else
        # Parse options
        set -l options "h/help" "l/list" "r/rank" "t/recent" "e/echo" "c/current" "x/delete"
        argparse $options -- $argv
        or return

        if set -q _flag_help
            echo "Usage: $_Z_CMD [-cehlrtx] args..." >&2
            return
        end

        set -l typ
        set -l list
        set -l echo
        set -l fnd (string join ' ' $argv)

        if set -q _flag_list
            set list 1
        end
        if set -q _flag_echo
            set echo 1
        end
        if set -q _flag_rank
            set typ "rank"
        end
        if set -q _flag_recent
            set typ "recent"
        end
        if set -q _flag_current
            set fnd "^$PWD $fnd"
        end
        if set -q _flag_delete
            sed -i -e "\:^$PWD|.*:d" "$datafile"
            return
        end

        [ -f "$datafile" ]; or return

        if test -n "$argv[1]"
            if test -d "$argv[1]"
                if test -z "$list"
                    cd "$argv[1]"
                    return
                end
            end
        end
        
        set -l result (_z_dirs | awk -v t=(date +%s) -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
            function frecent(rank, time) {
                dx = t - time
                return int(10000 * rank * (3.75/((0.0001 * dx + 1) + 0.25)))
            }
            function output(matches, best_match, common) {
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
            if test -n "$echo"
                echo "$result"
            else if test -d "$result"
                builtin cd "$result"
            end
        end
    end
end

# Wrapper function that enables the behavior to change directory
function z -d "jump to directory"
    if not set -q argv[1]
        return
    end
    
    set -l output (_z $argv)
    if test -d "$output"
        cd "$output"
    end
end

# Register completions
complete -c $_Z_CMD -a "(_z --complete (commandline -t))"

# Add directory on directory change
function _z_on_pwd --on-variable PWD
    status --is-command-substitution; and return
    _z --add "$PWD" &
end
```

The key changes are:
1. Modified the wrapper function `z` to handle the directory change
2. Added explicit output capturing and directory checking in the wrapper
3. Used `builtin cd` to ensure we're using the shell's built-in cd command

The wrapper function now properly handles the output from `_z` and changes directory when appropriate. This should now work as expected!
