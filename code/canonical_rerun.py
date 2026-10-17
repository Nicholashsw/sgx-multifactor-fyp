"""
Canonical re-run for the broad-universe paper. Single source of truth.
Requires: sg_broad_quarterly.csv (P-Q panel), World_Index_Constituents.csv, Monthly_World_Indices.csv
Produces every number in Tables 1-4 from ONE panel (P-Q, quarterly/TTM, 4-month lag).
Run:  python3 canonical_rerun.py
      SGX_PANEL=exports/sg_broad_quarterly.csv python3 canonical_rerun.py   # the SQL-built panel (sql/)
"""
import warnings; warnings.filterwarnings("ignore")
import pandas as pd, numpy as np, statsmodels.api as sm
from scipy import stats
import os, json

PANEL=os.environ.get('SGX_PANEL','sg_broad_quarterly.csv'); CONST='World_Index_Constituents.csv'; BENCH='more/Monthly_World_Indices.csv'
for f in [PANEL,CONST,BENCH]:
    if not os.path.exists(f): raise SystemExit(f"MISSING: {f}")

q=pd.read_csv(PANEL,parse_dates=['Date']).sort_values(['SecID','Date'])
q=q[q['Date']>='1991-01-01']
wc=pd.read_csv(CONST,parse_dates=['JuneDate']); wc['SecID']=wc['gvkey'].astype(str)+'_'+wc['iid'].astype(str)
snaps=sorted(wc['JuneDate'].unique())
def members(d):
    v=[s for s in snaps if s<=d]
    return set(wc[wc['JuneDate']==v[-1]]['SecID']) if v else None
mw=pd.read_csv(BENCH); mw['date']=pd.to_datetime(mw['date'])+pd.offsets.MonthEnd(0)
bench=mw[mw['fic']=='SGP'].set_index('date')['mportret']
dts=sorted(q['Date'].unique())
def tier_of(g):
    g=g.sort_values('MKT_CAP',ascending=False).reset_index(); g['r']=np.arange(len(g))
    g['Tier']=np.where(g['r']<30,'Large',np.where(g['r']<100,'Mid','Small')); return g.set_index('index')['Tier']
def alpha(r):
    df=pd.concat([r,bench],axis=1,keys=['s','b']).dropna()
    m=sm.OLS(df['s'],sm.add_constant(df['b'])).fit(cov_type='HAC',cov_kwds={'maxlags':6})
    return m.params['const']*100, m.tvalues['const'], m.params['b']
def perf(r):
    r=r.dropna(); c=(1+r).cumprod()
    return dict(ann=((1+r).prod()**(12/len(r))-1)*100, sharpe=r.mean()/r.std()*np.sqrt(12),
                mdd=((c-c.cummax())/c.cummax()).min()*100, n=len(r))
def nw_t(a):  # Newey-West t of the mean, 6 lags
    return sm.OLS(np.asarray(a),np.ones(len(a))).fit(cov_type='HAC',cov_kwds={'maxlags':6}).tvalues[0]
OUT={}

# ---- 0. UNIVERSE COUNTS (fixes the "352" error) ----
pit_n=[]
for d in dts:
    am=members(d)
    if am is None: continue
    pit_n.append(q[(q['Date']==d)&(q['SecID'].isin(am))]['SecID'].nunique())
OUT['universe']={'unfiltered_avg_per_month':float(q.groupby('Date')['SecID'].count().mean()),
                 'PIT_avg_per_month':float(np.mean(pit_n)),'PIT_min':int(np.min(pit_n)),'PIT_max':int(np.max(pit_n)),
                 'months':len(dts),'companies':int(q['SecID'].nunique())}
print("UNIVERSE:",OUT['universe'])

# ---- 1. TABLE 1: factor ICs on PIT universe, P-Q panel ----
# Next month's return, joined on the calendar so a gap in a stock's history leaves Fwd blank
# instead of pulling in a later month (shift(-1) did that on 433 rows).
nxt=q[['SecID','Date','Return_1M']].rename(columns={'Return_1M':'Fwd'}); nxt['Date']=nxt['Date']-pd.offsets.MonthEnd(1)
q=q.drop(columns='Fwd',errors='ignore').merge(nxt,on=['SecID','Date'],how='left')
zc=[c for c in q.columns if c.startswith('Z_')]+['Composite']
t1=[]
for c in zc:
    ics=[]
    for d,g in q.groupby('Date'):
        am=members(d)
        if am is None: continue
        sub=g[g['SecID'].isin(am)][[c,'Fwd']].dropna()
        if len(sub)>=15: ics.append(stats.spearmanr(sub[c],sub['Fwd'])[0])
    if len(ics)>50:
        a=np.array(ics); t1.append({'Factor':c,'Mean_IC':round(a.mean(),4),
            't_NW6':round(nw_t(a),2),'n':len(a)})
T1=pd.DataFrame(t1).sort_values('t_NW6',ascending=False); OUT['table1']=T1.to_dict('records')
print("\nTABLE 1 (PIT, P-Q):\n",T1.to_string(index=False))

# ---- 2. TABLE 2: survivor vs PIT, returns AND alphas from same panel ----
def bt(pit,tier=None,liq=False,score='Composite'):
    surv=set(q[q['Date']==dts[-1]]['SecID']); rows=[]
    for i,d in enumerate(dts[:-1]):
        c=q[q['Date']==d].dropna(subset=[score]).copy()
        if pit:
            am=members(d)
            if am is None: continue
            c=c[c['SecID'].isin(am)]
        else: c=c[c['SecID'].isin(surv)]
        if tier:
            if len(c)<40: continue
            c['Tier']=tier_of(c); c=c[c['Tier']==tier]
            if liq and c['Amihud'].notna().sum()>4: c=c[c['Amihud']<=c['Amihud'].quantile(.8)]
            k=max(3,len(c)//5)
        else:
            k=max(5,len(c)//10)
        if len(c)<(8 if tier else 20): continue
        c=c.sort_values(score,ascending=False)
        nd=dts[i+1]; nr=q[q['Date']==nd].drop_duplicates('SecID').set_index('SecID')['Return_1M']
        L=nr.reindex(c.head(k)['SecID']).mean(); S=nr.reindex(c.tail(k)['SecID']).mean()
        rows.append({'Date':nd,'Long':L-0.001,'LS':L-S-0.002,'n':len(c)})
    return pd.DataFrame(rows).set_index('Date')
t2=[]
for lbl,pit in [('Survivor-only',False),('Point-in-time',True)]:
    b=bt(pit)
    for leg in ['Long','LS']:
        p=perf(b[leg]); a,t,be=alpha(b[leg].dropna())
        t2.append({'Universe':lbl,'Leg':leg,'Ann%':round(p['ann'],1),'Sharpe':round(p['sharpe'],2),
                   'MaxDD%':round(p['mdd'],1),'Alpha%mo':round(a,2),'Alpha_t':round(t,2),'Beta':round(be,2)})
T2=pd.DataFrame(t2); OUT['table2']=T2.to_dict('records')
print("\nTABLE 2 (P-Q, returns+alphas same panel):\n",T2.to_string(index=False))

# ---- 3. TABLE 3: size tiers + liquidity screen ----
t3=[]
for tier in ['Large','Mid','Small']:
    b=bt(True,tier=tier); p=perf(b['LS']); a,t,be=alpha(b['LS'].dropna())
    ics=[]
    for d,g in q.groupby('Date'):
        am=members(d)
        if am is None: continue
        c=g[g['SecID'].isin(am)].dropna(subset=['Composite','Fwd']).copy()
        if len(c)<40: continue
        c['Tier']=tier_of(c); c=c[c['Tier']==tier]
        if len(c)>=8: ics.append(stats.spearmanr(c['Composite'],c['Fwd'])[0])
    ia=np.array(ics)
    t3.append({'Tier':tier,'AvgNames':int(b['n'].mean()),'IC':round(ia.mean(),4),
               'IC_t_NW6':round(nw_t(ia),2),'LS_Ann%':round(p['ann'],1),
               'LS_Sharpe':round(p['sharpe'],2),'Alpha%mo':round(a,2),'Alpha_t':round(t,2),'Beta':round(be,2)})
b=bt(True,tier='Small',liq=True); p=perf(b['LS']); a,t,be=alpha(b['LS'].dropna())
t3.append({'Tier':'Small (liq-screen)','AvgNames':int(b['n'].mean()),'IC':None,'IC_t_NW6':None,
           'LS_Ann%':round(p['ann'],1),'LS_Sharpe':round(p['sharpe'],2),'Alpha%mo':round(a,2),
           'Alpha_t':round(t,2),'Beta':round(be,2)})
T3=pd.DataFrame(t3); OUT['table3']=T3.to_dict('records')
print("\nTABLE 3 (PIT tiers, P-Q):\n",T3.to_string(index=False))

# ---- 4. TABLE 4: composite weighting schemes, PIT ----
# Composite is the panel's pre-set weights, renormalised over the factors present, at least 4 of 8.
# Z_LogMktCap is signed small-cap (z of -log mcap) and Z_Amihud liquid (z of -Amihud).
ZC=['Z_MOM_12_1','Z_MOM_6_1','Z_BM_Ratio','Z_DIV_YIELD','Z_EY','Z_ROE','Z_LogMktCap','Z_Amihud']
PRESET={'Z_MOM_12_1':.20,'Z_MOM_6_1':.05,'Z_BM_Ratio':.20,'Z_DIV_YIELD':.10,'Z_EY':.10,'Z_ROE':.20,'Z_LogMktCap':.05,'Z_Amihud':.10}
def wscore(df,w,cols,min_n=4):
    Z=df[cols]; W=pd.Series(w).reindex(cols).fillna(0.0)
    s=(Z.fillna(0)*W).sum(axis=1)/Z.notna().mul(W).sum(axis=1).replace(0,np.nan)
    return s.where(Z.notna().sum(axis=1)>=min_n)
assert np.allclose(wscore(q,PRESET,ZC),q['Composite'],atol=1e-9,equal_nan=True)
q['Composite_ExQuality']=wscore(q,{k:v for k,v in PRESET.items() if k!='Z_ROE'},[c for c in ZC if c!='Z_ROE'])
q['Composite_Equal']=wscore(q,{c:1.0 for c in ZC},ZC)
# Walk-forward: each month's weights are the mean of past monthly PIT ICs only (dates before it,
# using the calendar-join Fwd, at least 15 names per date, expanding window), negatives set to
# zero, rescaled to sum to 1; equal weights until a factor has 36 months of ICs.
icm={}
for d,g in q.groupby('Date'):
    am=members(d)
    if am is None: continue
    g=g[g['SecID'].isin(am)]; icm[d]={}
    for c in ZC:
        sub=g[[c,'Fwd']].dropna()
        if len(sub)>=15: icm[d][c]=stats.spearmanr(sub[c],sub['Fwd'])[0]
icm=pd.DataFrame.from_dict(icm,orient='index').reindex(columns=ZC).sort_index()
q['Composite_WF']=np.nan
for d,idx in q.groupby('Date').groups.items():
    h=icm[icm.index<d]; mu=h.mean().where(h.notna().sum()>=36).clip(lower=0).fillna(0)
    w=(mu/mu.sum()).to_dict() if mu.sum()>0 else {c:1/len(ZC) for c in ZC}
    q.loc[idx,'Composite_WF']=wscore(q.loc[idx],w,ZC)
t4=[]
for c in ['Composite','Composite_ExQuality','Composite_Equal','Composite_WF']:
    ics=[]
    for d,g in q.groupby('Date'):
        am=members(d)
        if am is None: continue
        sub=g[g['SecID'].isin(am)][[c,'Fwd']].dropna()
        if len(sub)>=15: ics.append(stats.spearmanr(sub[c],sub['Fwd'])[0])
    ia=np.array(ics); b=bt(True,score=c); a,t,be=alpha(b['LS'].dropna())
    t4.append({'Score':c,'Mean_IC':round(ia.mean(),4),'t_NW6':round(nw_t(ia),2),'n':len(ia),
               'LS_Alpha%mo':round(a,2),'LS_Alpha_t':round(t,2)})
T4=pd.DataFrame(t4); OUT['table4']=T4.to_dict('records')
print("\nTABLE 4 (PIT, composite weighting):\n",T4.to_string(index=False))

json.dump(OUT,open('canonical_results.json','w'),indent=1,default=str)
T1.to_csv('canonical_table1.csv',index=False); T2.to_csv('canonical_table2.csv',index=False); T3.to_csv('canonical_table3.csv',index=False)
T4.to_csv('canonical_table4.csv',index=False)
print("\nSaved canonical_results.json + canonical_table{1,2,3,4}.csv")
