#!/usr/bin/env python3
"""Reproducible participant-separated XGBoost research experiment. No iPhone accuracy claim."""
import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import platform

import numpy as np
from sklearn.metrics import roc_auc_score, confusion_matrix, log_loss
from sklearn.model_selection import GroupShuffleSplit
import xgboost as xgb
import coremltools as ct
from coremltools.models.tree_ensemble import TreeEnsembleRegressor

NAMES = ['mean_interval_ms', 'sdnn_ms', 'rmssd_ms', 'pnn50', 'interval_cv']
VERSION = 'liu-window-xgb-v1'


def main(path, output):
    output.mkdir(parents=True, exist_ok=True)
    rows = list(csv.DictReader(path.open()))
    usable = [r for r in rows if r['usable'] == '1']
    dev = [r for r in usable if r['source_split'] == 'development']
    test = [r for r in usable if r['source_split'] == 'test']
    def arrays(records):
        return (np.array([[float(r[n]) for n in NAMES] for r in records], dtype=np.float32),
                np.array([int(r['afib_label']) for r in records]),
                np.array([r['participant_id'] for r in records]))
    xd, yd, gd = arrays(dev)
    xt, yt, gt = arrays(test)
    train, validation = next(GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=42).split(xd, yd, gd))
    assert not (set(gd[train]) & set(gd[validation]) or set(gd) & set(gt))
    assert all(len(set(y)) == 2 for y in [yd[train], yd[validation], yt])
    counts = Counter(gd[train])
    weights = np.array([1/counts[g] for g in gd[train]])
    weights *= len(weights)/weights.sum()
    ratio = weights[yd[train] == 0].sum() / weights[yd[train] == 1].sum()
    model = xgb.XGBClassifier(n_estimators=400, learning_rate=0.05, max_depth=3,
        min_child_weight=10, subsample=0.8, colsample_bytree=1, reg_lambda=10,
        base_score=0.5, n_jobs=4, random_state=42, eval_metric='logloss',
        early_stopping_rounds=30, scale_pos_weight=float(ratio))
    model.fit(xd[train], yd[train], sample_weight=weights,
              eval_set=[(xd[validation], yd[validation])], verbose=False)
    booster = model.get_booster()[:model.best_iteration+1]
    booster.feature_names = NAMES
    booster.save_model(output / 'AFibResearch.xgb.json')
    def scores(x):
        return booster.predict(xgb.DMatrix(x, feature_names=NAMES))
    pv = scores(xd[validation])
    # Select conservative abstention thresholds on development validation only.
    # Test outputs have not been inspected at this point.
    candidates = np.linspace(0.01, 0.99, 199)
    high = min([t for t in candidates if t >= 0.5 and np.mean(pv[yd[validation] == 0] < t) >= 0.95] or [0.999999])
    low = max([t for t in candidates if t <= 0.5 and np.mean(pv[yd[validation] == 1] > t) >= 0.95] or [0.000001])
    frozen = {'version': VERSION, 'train_participants': sorted(set(gd[train])),
              'validation_participants': sorted(set(gd[validation])), 'test_participants': sorted(set(gt)),
              'lowerThreshold': float(low), 'upperThreshold': float(high),
              'boosting_rounds': booster.num_boosted_rounds(), 'seed': 42,
              'featureVersion': 'pulse-window-v1', 'featureNames': NAMES,
              'features_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    (output / 'frozen_protocol.json').write_text(json.dumps(frozen, indent=2)+'\n')
    # Frozen protocol above precedes final held-out test evaluation.
    pt = scores(xt)
    def metrics(y, p):
        tn, fp, fn, tp = confusion_matrix(y, p >= 0.5, labels=[0,1]).ravel()
        accepted = (p <= low) | (p >= high)
        selective = confusion_matrix(y[accepted], p[accepted] >= high, labels=[0,1]).tolist()
        return {'segments': len(y), 'afib_segments': int(y.sum()), 'auc': float(roc_auc_score(y,p)),
                'log_loss': float(log_loss(y,p)), 'sensitivity_at_0_5': float(tp/(tp+fn)),
                'specificity_at_0_5': float(tn/(tn+fp)), 'confusion_at_0_5_tn_fp_fn_tp': [int(tn),int(fp),int(fn),int(tp)],
                'classified_fraction': float(accepted.mean()), 'inconclusive_fraction': float(1-accepted.mean()),
                'selective_confusion_rows_true_cols_predicted': selective}
    report = {'version': VERSION, 'protocol': frozen,
              'training': metrics(yd[train], scores(xd[train])),
              'development_validation': metrics(yd[validation], pv), 'held_out_test': metrics(yt,pt),
              'exclusions': {split: dict(Counter(r['original_label'] for r in rows if r['source_split']==split and r['usable']=='0')) for split in ['development','test']},
              'retained_by_original_test_label': dict(Counter(r['original_label'] for r in test)),
              'environment': {'python':platform.python_version(), 'xgboost':xgb.__version__, 'numpy':np.__version__, 'coremltools':ct.__version__},
              'limitations': ['Original validation cohort repurposed as development training/validation; this is a new experiment, not reproduction of the paper.',
                  'Held-out test metrics apply to retained 10-second source-sensor windows, not 30-second iPhone recordings.',
                  'Quality exclusions are reported by original rhythm subtype; non-AFib is not equivalent to normal rhythm.',
                  'No ECG-confirmed iPhone validation, calibrated individual risk, clinical utility or diagnostic accuracy is established.',
                  'Repository reuse/model redistribution terms need confirmation before distributing trained artifacts.']}
    rng=np.random.default_rng(42)
    participants=np.unique(gt)
    draws=[]
    for _ in range(1000):
        indices=np.concatenate([np.flatnonzero(gt==g) for g in rng.choice(participants,len(participants),replace=True)])
        if len(np.unique(yt[indices]))==2:
            m=metrics(yt[indices],pt[indices]);draws.append([m['auc'],m['sensitivity_at_0_5'],m['specificity_at_0_5']])
    ci=np.quantile(np.array(draws),[0.025,0.975],axis=0)
    report['held_out_test']['participant_bootstrap_95_ci']={k:ci[:,i].tolist() for i,k in enumerate(['auc','sensitivity_at_0_5','specificity_at_0_5'])}
    report['held_out_test']['by_original_label']={str(k): {'retained_segments':int(sum(int(r['original_label'])==k for r in test)),
        'mean_afib_score':float(np.mean(pt[np.array([int(r['original_label'])==k for r in test])]))} for k in range(6)}
    contributions=booster.predict(xgb.DMatrix(xt,feature_names=NAMES),pred_contribs=True)
    report['held_out_test']['mean_absolute_tree_shap_log_odds']={n:float(v) for n,v in zip(NAMES,np.abs(contributions[:,:5]).mean(axis=0))}
    (output/'evaluation.json').write_text(json.dumps(report,indent=2)+'\n')
    # Scalar Core ML output: logistic(sum of learned leaf values), base margin 0 (base_score=.5).
    # Avoid unsupported converter assumptions about current XGBoost feature-name formats.
    builder=TreeEnsembleRegressor([(n,ct.models.datatypes.Double()) for n in NAMES], 'afibProbability')
    builder.set_default_prediction_value(0.0)
    builder.set_post_evaluation_transform('Regression_Logistic')
    portable=[]
    for tree_id,text in enumerate(booster.get_dump(dump_format='json')):
        root=json.loads(text); nodes=[]
        def add(node):
            item={'id':node['nodeid']}
            if 'leaf' in node:
                value=float(np.float32(node['leaf']))
                builder.add_leaf_node(tree_id,node['nodeid'],value)
                item['leaf']=value
            else:
                feature=NAMES.index(node['split'])
                threshold=float(np.float32(node['split_condition']))
                builder.add_branch_node(tree_id,node['nodeid'],feature,threshold,'BranchOnValueLessThan',node['yes'],node['no'],missing_value_tracks_true_child=node['missing']==node['yes'])
                item.update({'feature':feature,'threshold':threshold,'yes':node['yes'],'no':node['no']})
                for child in node['children']:add(child)
            nodes.append(item)
        add(root);portable.append(sorted(nodes,key=lambda n:n['id']))
    builder.spec.description.metadata.shortDescription='Experimental AFib vs other-rhythm source-sensor model. Not validated for iPhone diagnosis.'
    builder.spec.description.metadata.author='Atrio local research experiment using Liu et al. public data'
    ct.utils.save_spec(builder.spec,str(output/'AFibResearch.mlmodel'))
    # Fixed training-only background for exact interventional Shapley explanations.
    background=xd[train][rng.choice(len(train),size=min(32,len(train)),replace=False)]
    explanation={'featureNames':NAMES,'baseMargin':0.0,'trees':portable,'background':background.tolist()}
    (output/'AFibResearch.explainer.json').write_text(json.dumps(explanation,separators=(',',':'))+'\n')
    with (output/'parity_vectors.jsonl').open('w') as stream:
        # Includes real windows and exact Float32 tree thresholds to test branching semantics.
        vectors=list(xt[:1000])
        for tree in portable[:30]:
            for node in tree:
                if 'feature' in node:
                    for value in [np.nextafter(np.float32(node['threshold']),np.float32(-np.inf)),np.float32(node['threshold']),np.nextafter(np.float32(node['threshold']),np.float32(np.inf))]:
                        v=xt[0].copy();v[node['feature']]=value;vectors.append(v)
        expected=scores(np.asarray(vectors,dtype=np.float32))
        for x,p in zip(vectors,expected):
            stream.write(json.dumps({'features':dict(zip(NAMES,map(float,x))),'expected':float(p)})+'\n')
    manifest={'version':VERSION,'algorithmVersion':'pulse-v1','featureVersion':'pulse-window-v1',
              'evaluationSummary':f"Held-out source-sensor windows: AUC {report['held_out_test']['auc']:.3f}. Not evaluated on iPhone recordings.",
              'lowerThreshold':float(low),'upperThreshold':float(high),'windowSeconds':10,'minimumWindows':2,
              'sourceDomain':'Liu et al. 100 Hz source-sensor PPG; no ECG-confirmed iPhone validation',
              'coreMLParityVerified':False,'modelSHA256':hashlib.sha256((output/'AFibResearch.mlmodel').read_bytes()).hexdigest()}
    (output/'AFibResearch.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'train_participants':len(set(gd[train])),'validation_participants':len(set(gd[validation])),'test_participants':len(set(gt)),
                      'rounds':booster.num_boosted_rounds(),'thresholds':[low,high],'held_out_test':report['held_out_test']},indent=2),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('features',type=Path);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();main(args.features,args.output)
