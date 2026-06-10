# Quant Reading List — From FYP to Hedge Fund

A curated reading list to take you from your SGX multi-factor FYP to building production trading strategies. Read in the suggested order — each paper builds on the previous ones.

---

## TIER 1 — Foundations (read first, in this order)

**01. Fama & French (1993)** — Common Risk Factors in the Returns on Stocks and Bonds
The paper that started modern factor investing. Three-factor model: market + size (SMB) + value (HML). Every quant manager has read this. Mathematical setup is straightforward; focus on Section II (factor construction) and Section IV (regression results). 3.3 MB.

**02. Jegadeesh & Titman (1993)** — Returns to Buying Winners and Selling Losers
The momentum paper. Demonstrates that buying past 3-12 month winners and selling losers generates significant excess returns. Section IV is the empirical core — the J/K momentum sort methodology you'll reuse in any cross-sectional momentum work. 608 KB.

**03. Carhart (1997)** — On Persistence in Mutual Fund Performance
Adds momentum (UMD) to Fama-French as the fourth factor. Shows mutual fund "skill" is mostly factor exposure. Required to understand performance attribution and why beating factor models is hard. 3.1 MB.

**04. Amihud (2002)** — Illiquidity and Stock Returns
Defines the Amihud illiquidity ratio you used in your FYP. Documents the illiquidity premium globally. Critical for any small-cap or emerging-market strategy. 197 KB.

---

## TIER 2 — Advanced Factor Investing (after Tier 1)

**05. Asness, Moskowitz & Pedersen (2013)** — Value and Momentum Everywhere ★★★
AQR's signature paper. Demonstrates value + momentum work in 8 asset classes simultaneously. This is *the* paper for multi-asset quant strategies. Read it twice. The negative correlation between value and momentum is the key insight you'd build a hedge fund around. 2.1 MB.

**06. Frazzini & Pedersen (2014)** — Betting Against Beta (BAB)
Low-beta stocks earn higher risk-adjusted returns than CAPM predicts. The BAB factor has Sharpe ~0.75 in US equities over 80+ years — higher than value or momentum. Funding-constraint explanation is elegant. AQR runs billions on this. 1.7 MB (NBER) / 1.4 MB (published).

**07. Moskowitz, Ooi & Pedersen (2012)** — Time Series Momentum
Different from cross-sectional momentum. Trend-following systematically: long assets that went up the past year, short ones that went down. The foundation of CTA/managed futures industry. AQR's main trend-following fund is built on this. 953 KB.

**08. Asness, Frazzini & Pedersen (2019)** — Quality Minus Junk
QMJ factor: long high-quality (profitable, stable, growing) stocks, short low-quality. Negatively correlated with value — completes the AQR factor zoo. Section 3 (quality measures) is the practical takeaway. 580 KB.

**09. Israel & Moskowitz (2013)** — The Role of Shorting, Firm Size, and Time on Market Anomalies
Honest assessment of which factor returns survive in long-only and large-cap implementations. Useful for understanding capacity constraints — directly relevant to your "small universe" concern. 2.5 MB.

---

## TIER 3 — Statistical Rigour and Backtesting (CRITICAL)

These are what separates real quants from people who fit curves to noise. Read carefully — they will save you from making expensive mistakes when you trade real capital.

**10. Bailey & Lopez de Prado (2014)** — The Deflated Sharpe Ratio ★★★
Most reported Sharpe ratios in backtests are statistical noise. This paper teaches you how to compute the *true* Sharpe ratio after adjusting for multiple testing and non-normality. Apply this to your FYP — your composite Sharpe of 0.515 will deflate, but you'll have an honest number. 1.0 MB.

**11. Harvey & Liu (2014)** — Evaluating Trading Strategies
Multiple-testing corrections (Bonferroni, BHY, Holm) for trading strategies. If you've tried 100 variants and the best one has Sharpe 1.0, the haircut is brutal. Mandatory before you publish or trade anything. 2.4 MB.

**12. Harvey & Liu — Lucky Factors**
Same authors, more recent. New methodology to identify which factors are genuine alpha sources vs lucky outcomes of data mining across 300+ candidate factors. 372 KB.

**13. Lopez de Prado — Deflating the Sharpe Ratio (Slides)**
The companion slides to paper 10. Easier visual introduction. Read this first, then paper 10. 1.2 MB.

---

## TIER 4 — Execution and Microstructure (for when you go live)

**14. Almgren & Chriss (2000)** — Optimal Execution of Portfolio Transactions ★★★
The foundational paper on optimal trade execution. Balances market impact vs timing risk when liquidating positions. Every execution algo (VWAP, TWAP, Implementation Shortfall) traces back to this. Essential for production systems. 332 KB.

**15. O'Hara (2015)** — High Frequency Market Microstructure
Modern microstructure: how HFT changed price formation, adverse selection, and what it means for quant strategies operating below the daily horizon. Read after Almgren-Chriss. 893 KB.

---

## TIER 5 — Portfolio Construction Theory

**16. Zhou (2008) — Fundamental Law of Active Management Redux**
The math behind IR = IC × √Breadth (Grinold's law). The exact paper you need to understand why your SGX strategy has the IR it does, and what would change with bigger universes. Read before pitching to any institutional allocator. 150 KB.

---

## What's Missing — Buy These Books

**López de Prado — Advances in Financial Machine Learning (2018)**
~$70 on Amazon. The single most important book for modern quant. Covers proper backtesting (combinatorial purged cross-validation), feature engineering for financial data, fractional differentiation, meta-labeling. If you want to do ML in finance correctly, you need this. The mistakes it catches will save you millions in real money.

**Pedersen — Efficiently Inefficient (2015)**
~$30. Lasse Pedersen (AQR principal) walks through every major hedge fund strategy with practitioner-level detail. The chapter on factor investing is the best summary in print. Interviews with Asness, Griffin, Soros, Paulson are bonus.

**Grinold & Kahn — Active Portfolio Management (2nd ed)**
~$60. The bible of quantitative portfolio construction. Where the Fundamental Law was first published. Chapters 6-10 (forecasting, information ratio, breadth) are the most relevant for your work.

**Narang — Inside the Black Box (2013)**
~$40. Less mathematical, but the best business-level overview of how quant hedge funds actually operate — strategy types, risk management, technology stack, capital raising. Read this before pitching to allocators.

---

## Suggested Reading Order

**Month 1:** Papers 01, 02, 03, 04 (foundations — you've already read 01, 02, 04 partially for your FYP)

**Month 2:** Papers 05, 06, 07 (the AQR factor stack — this is where you'll find your next strategy ideas)

**Month 3:** Papers 10, 11, 13 (statistical rigour — read alongside re-running your FYP backtest with deflated Sharpe)

**Month 4:** Papers 14, 15 + buy López de Prado book (execution + ML methodology)

**Month 5:** Books — Pedersen, Grinold & Kahn (deeper theoretical foundations)

**Month 6:** Apply everything to a new strategy idea, target a Sharpe > 1.0 with deflated metrics, position size with Kelly criterion, design execution algo before going live with real capital.

---

## Strategy Build Roadmap (FYP → Hedge Fund)

1. **Year 1 (now → 2027):** Get a quant analyst role at Citadel, Point72/Cubist, or BAM. The papers above + your FYP get you to first-round interviews. AQR or Two Sigma if you can.

2. **Year 2-3:** Build personal track record on paper trading or with small personal capital. Live track record beats any backtest when raising capital.

3. **Year 4-5:** Approach family offices and seeders (Investcorp-Tages, PAAMCO Launchpad). SGD 5-20M of seed capital. CMS license from MAS.

4. **Year 5+:** External capital, scale, hire. By year 7-10 you can be running USD 100M-1B.

The papers above are necessary but not sufficient. The sufficient part is execution, capital, and patience.

---

*Nicholas Hong | Built for educational and research purposes. Not financial advice.*
