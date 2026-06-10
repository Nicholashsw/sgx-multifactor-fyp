#!/bin/bash
cd /home/claude/quant_papers

declare -a urls=(
  "01_Fama_French_1993_Three_Factor.pdf|https://www.bauer.uh.edu/rsusmel/phd/Fama-French_JFE93.pdf"
  "02_Jegadeesh_Titman_1993_Momentum.pdf|https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf"
  "03_Amihud_2002_Illiquidity.pdf|https://www.cis.upenn.edu/~mkearns/finread/amihud.pdf"
  "04_Asness_Moskowitz_Pedersen_2013_Value_Momentum_Everywhere.pdf|https://w4.stern.nyu.edu/facdir/lpederse/papers/ValMomEverywhere.pdf"
  "05_Frazzini_Pedersen_2014_Betting_Against_Beta.pdf|https://pages.stern.nyu.edu/~lpederse/papers/BettingAgainstBeta.pdf"
  "06_Moskowitz_Ooi_Pedersen_2012_Time_Series_Momentum.pdf|https://w4.stern.nyu.edu/facdir/lpederse/papers/TimeSeriesMomentum.pdf"
  "07_Bailey_LopezDePrado_2014_Deflated_Sharpe_Ratio.pdf|https://www.davidhbailey.com/dhbpapers/deflated-sharpe.pdf"
  "08_Harvey_Liu_2014_Evaluating_Trading_Strategies.pdf|https://www.stat.berkeley.edu/~aldous/157/Papers/harvey.pdf"
  "09_Harvey_Liu_Lucky_Factors.pdf|https://jacobslevycenter.wharton.upenn.edu/wp-content/uploads/2015/05/Lucky-Factors.pdf"
  "10_Almgren_Chriss_2000_Optimal_Execution.pdf|https://www.smallake.kr/wp-content/uploads/2016/03/optliq.pdf"
  "11_Zhou_2008_Fundamental_Law_Active_Mgmt.pdf|http://gyanresearch.wdfiles.com/local--files/alpha/JPM_SU_08_ZHOU.pdf"
  "12_Clarke_deSilva_Thorley_2006_Fundamental_Law.pdf|https://joim.com/wp-content/uploads/emember/downloads/p0158.pdf"
  "13_OHara_2015_High_Frequency_Microstructure.pdf|https://statmath.wu.ac.at/~hauser/LVs/FinEtricsQF/References/oHara2015JFinEco_HighFrequ_Market_MiicroStruct.pdf"
  "14_Frazzini_Pedersen_BAB_Published.pdf|https://research-api.cbs.dk/ws/portalfiles/portal/60082899/lasse_heje_pedersen_et_al_betting_against_beta_publishersversion.pdf"
  "15_LopezDePrado_Deflating_Sharpe_Slides.pdf|https://pdfs.semanticscholar.org/c215/d0a2064ce1a3565d276475abc84305418f0f.pdf"
)

success=0
failed=0
for entry in "${urls[@]}"; do
  fname="${entry%%|*}"
  url="${entry##*|}"
  printf "  %-65s " "$fname"
  curl -sL -o "$fname" --max-time 30 -A "Mozilla/5.0 (X11; Linux x86_64)" "$url" 2>/dev/null
  if [ -f "$fname" ]; then
    size=$(stat -c%s "$fname" 2>/dev/null || echo 0)
    if [ "$size" -gt 50000 ]; then
      echo "OK ($((size/1024))KB)"
      success=$((success+1))
    else
      echo "TOO SMALL ($((size))B), removing"
      rm -f "$fname"
      failed=$((failed+1))
    fi
  else
    echo "FAIL"
    failed=$((failed+1))
  fi
done
echo ""
echo "Success: $success / $((success+failed))"
