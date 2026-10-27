"""Record the runtime author's separate review of the verifier's certificate."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).parent
OUTPUT = ROOT / "tests/balance/results/act1-adjustment-v03"
files = [HERE / name for name in ("verify_proof_review.py", "verify_recovery_bound.gd", "recovery-bound-certificate.md", "controller.gd", "controller_factory.gd")]
files.append(ROOT / "scripts/boulder_controller.gd")
review = {
    "reviewer_role": "runtime author, independent of proof author; this is proof review, not self-approval of the runtime",
    "status": "conditionally_accepted_source_equation_certificate",
    "scope": "G190/B80: continuous 190m dry STONE45, grip1/resistance.2, 120Hz, push drain scale1, no internal shelf/ledge/support/purchase/external forward impulse, fixed ranks, entry S<=capacity and v<=1.8, min stamina1, released recovery rate7 and time quota80/7",
    "findings": [
        {"topic": "positive velocity friction", "assessment": "For old v>.001 and no slip, a<=F-(g+r). Semi-implicit H=c*x+positive(v)^2/2 yields deltaH=(a+c)*v_next*dt-(a*dt)^2/2<=F*v_next*dt. Speed clipping only lowers effective acceleration. If new velocity is nonpositive H cannot increase."},
        {"topic": "crosszero and stiction", "assessment": "The proof correctly avoids using c=g+r as the negative-velocity opposing force. With old v<=.001, g>r and rollback force reduction imply v_next<=.001+F0*dt. Dropping old positive kinetic energy gives the stated R_low bound. Bracing clamps positive outcomes to zero, and slip removes forward momentum, so neither supplies positive H."},
        {"topic": "tier recovery cycles", "assessment": "E(S)=integral_0^S rho(u+q)du is nondecreasing and 1-Lipschitz. For paid d<=q, every u in [S-d,S] obeys u+q>=S, hence E drop>=rho(S)*d. Repeated crossings of 20% and 50% tiers do not invalidate telescoping. E(C)=.885*C+.35*q is correct for the audited capacities."},
        {"topic": "final unpaid drain", "assessment": "If S<d<=q=.0425 then rho=.65, leaving at most .65*q unpaid weighted drain. Min stamina1 makes S=0 absorbing while inside the gate, so there is at most one such step after the last lower-boundary entry. The essential condition is strictly positive recovery_min_stamina; min1>=q is sufficient, but that stronger inequality is not needed for this proof. With min0 this certificate is invalid."},
        {"topic": "quota and cap", "assessment": "Eligible_dt=min(dt,remaining time) handles the last fractional opportunity. Actual increase=min(missing stamina,r*R*eligible_dt); eligible time is consumed even at cap. Therefore total actual recovery<=r*T*R. Retreat/reentry cannot refund the ledger. On a fresh final entry, allowing the full original quota is an overestimate and remains safe."},
        {"topic": "entry and scope", "assessment": "Subtracting 1.8/120=.015m from the gate length covers the discrete lower-boundary crossing step. Entry kinetic energy<=1.62. The resulting shortage5.626722965051 is positive. This does not certify other drain scales, geometry, wet surfaces, min0, dynamic ranks, safe retreat, human time, or IEEE formal correctness."},
    ],
    "counterexample_found": False,
    "verification_distinction": "The conceptual review above is independent. The exact-rational result below reruns the proof author's existing verification function; it is corroboration, not an independently implemented dynamics model or exhaustive proof.",
    "rational_rerun": json.loads((OUTPUT / "proof-independent-rational-rerun.json").read_text()),
    "source_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files},
}
(OUTPUT / "independent-proof-review.json").write_text(json.dumps(review, ensure_ascii=False, indent=2), encoding="utf-8")
commands = """Run from repository root, Godot 4.5.1:
& .tools/godot/Godot_v4.5.1-stable_win64_console.exe --headless --path . --script tests/balance/adjustment_v03/verify_runtime.gd
python tests/balance/adjustment_v03/audit_preserved_sources.py
python tests/balance/adjustment_v03/record_independent_proof_review.py

runtime-verification.json: 514 checks / 0 failures.
runtime-verification.log.txt: captured engine/stdout/stderr from re-execution.
preserved-source-audit.json: 99 recorded source/data/evidence/CSV hash comparisons / 0 differences.
No production/v0.2 file is written by this review. The source audit covers recorded manifest paths, not unrelated user UI/design/untracked files.
"""
(OUTPUT / "runtime-verification-reproduce.txt").write_text(commands, encoding="utf-8")
print(json.dumps({"status": review["status"], "counterexample_found": False, "shortage": review["rational_rerun"]["shortage"]}))
