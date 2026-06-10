#!/bin/bash
cd /home/claude/quant_papers

declare -a extras=(
  "16_Carhart_1997_Persistence_Mutual_Funds.pdf|http://finance.martinsewell.com/fund-performance/Carhart1997.pdf"
  "17_Israel_Moskowitz_2013_Shorting_Size_Time.pdf|https://gritcap.com/enoalroa/2020/10/Israel-and-Moskowitz-The-role-of-shorting-firm-size-and-time-on-market-anomalies-2012.pdf"
  "18_Asness_Frazzini_Pedersen_QualityMinusJunk.pdf|http://www.econ.yale.edu/~shiller/behfin/2013_04-10/asness-frazzini-pedersen.pdf"
)

for entry in "${extras[@]}"; do
  fname="${entry%%|*}"
  url="${entry##*|}"
  printf "  %-65s " "$fname"
  curl -sL -o "$fname" --max-time 30 -A "Mozilla/5.0 (X11; Linux x86_64)" "$url" 2>/dev/null
  if [ -f "$fname" ]; then
    size=$(stat -c%s "$fname" 2>/dev/null || echo 0)
    if [ "$size" -gt 50000 ]; then
      echo "OK ($((size/1024))KB)"
    else
      echo "TOO SMALL"; rm -f "$fname"
    fi
  fi
done
echo ""
echo "Final paper list:"
ls -la *.pdf
