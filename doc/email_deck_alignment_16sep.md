# Draft e-mail — 16 Sep 2026

**To:** Jip, Chris, Lewis
**Subject:** Benchmarking deck — a few fixes and one vocabulary for the Ispra seminar

Hi Jip, Chris, Lewis,

I went through the current "Benchmarking access to pharmacies" draft next to Rosa Figueiredo's La Poste deck and our sweep deck. The story holds up well. Below are the points I would fix or align before Thursday, in order of importance. Everything I refer to is in the updated `doc/lambda_sweep5.pptx` (16 Sep), so you can copy slides or charts straight from it.

1. **Three slides are older copies of ours.** Your p15 (frontier schematic), p16 (scenarios) and p27 (how one λ picks one point) still say S1/S2 are the closest sweep point and that the coarse grid runs to 1e3. Since #52 both are pinned by bisection over λ, to within one facility and 0.2% travel, on a 1-2-5 grid from 1e-4 to 5. The refreshed versions are our p13, p11 and p10; they also now use y for "open" and x for "assignment", the notation Rosa uses.

2. **The three result charts (p18–20) are the July generation.** Italy Sud is still on the ESPON pharmacy list, which was missing three pharmacies in five: the baseline shows about 1,250 cells where the OECD list gives 3,187. Denmark and PACA are unchanged in count but the S1/S2 markers moved with the pinning. Our p25, p44 and p47 are the current versions; p17 has the Denmark-style maps for the Netherlands.

3. **The "revealed preference" map (p23) inherits the same Italian artefact.** ITF and ITG show as high-λ because the old list made them look under-supplied; on the OECD data they move to the low end. Hungary and Finland are marked "no sweep data" but both are swept now (our p31–32). The ranking to use is our p72–73.

4. **Cost function slide (p13).** The fitted line is the school cost function, and the x-axis still reads "n pupils". I would label it as the placeholder it is, or leave it out; nothing in the frontier or the rankings depends on the €100,000 per location.

5. **One vocabulary.** We adopted your name **cross-lambda** for the λ at the balanced-improvement crossing, and Rosa's names for the objects around it: pMP for the fixed-count problem, CpMP for the capacitated one, MCLP for coverage, territorial coverage constraints for ≥1 per zone, RIC for the travel above the optimum at equal p. Our p67 is a one-page bridge between the three decks; feel free to reuse it.

6. **Cross-lambda by regime (p24), one caveat worth a sentence.** For one and the same geography, cross-lambda is lower the more pharmacies there are today. So across countries it moves with residents per pharmacy as well as with policy, and the rule-of-law group is also the group with the smallest catchments. A scatter of cross-lambda against residents per pharmacy would show how much is geography; we can produce it from the existing metrics.

7. **Two things from your next-steps slide we can deliver without new solves:** the S1/S2 gains split by degree of urbanisation (the DEGURBA grid is already in the model), and a policy-versus-geography split of today's travel on the frontier. Rosa's closure-only and addition-only curves are the natural way to answer your two p4 questions; both are on our roadmap (p65).

8. **Wording.** We changed our agenda text to match your trilemma slide: demand density is given, so the trilemma collapses to proximity versus efficiency. Same idea, now the same words.

Happy to send the refreshed PNGs separately if that is easier than lifting them from the deck.

Best,
Maarten
