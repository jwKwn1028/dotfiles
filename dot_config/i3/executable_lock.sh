#!/usr/bin/env bash
# i3lock-color comes from run_once_after_95; stock i3lock is the fallback.
case "$(i3lock --version 2>&1)" in
    *.c.*)
        exec i3lock -n -c 292d3e \
            --radius=60 --ring-width=6 \
            --inside-color=00000000 --insidever-color=00000000 --insidewrong-color=00000000 \
            --ring-color=7aa2f7 --ringver-color=7dcfff --ringwrong-color=f7768e \
            --keyhl-color=86be43 --bshl-color=ff9e64 \
            --line-color=00000000 --separator-color=00000000 \
            --verif-color=c0caf5 --wrong-color=f7768e --modif-color=e0af68 \
            --verif-font=JuliaMono --wrong-font=JuliaMono \
            --verif-size=15 --wrong-size=15 --modif-size=11
        ;;
esac
exec i3lock -n -c 292d3e
