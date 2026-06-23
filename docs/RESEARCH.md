# Living Waters Research Notes

Living Waters is a game simulation, not veterinary advice. Species values are conservative starting values derived from public references and should be refined as the roster grows.

## Source Policy

- Prefer FishBase for identity, taxonomy, size, diet, range, and habitat.
- Prefer veterinary and aquaculture references for water-quality risks.
- Record uncertainty rather than forcing exact values.
- Keep facts, ranges, and links; do not copy full copyrighted text.

## Current Sources

- FishBase species summaries for `Paracheirodon innesi`, `Betta splendens`, `Danio rerio`, and corydoras relatives.
- Merck Veterinary Manual aquatic-system water-quality disease overview.
- FAO aquaculture water-quality material.
- Peer-reviewed aquarium welfare and ornamental-fish care references available through PubMed Central.
- IUCN Red List is included as a conservation-status lookup source for species where appropriate.

## Scientific Simplifications In V1

- Chemistry is parameterized for gameplay and does not solve full carbonate equilibrium.
- Toxic un-ionized ammonia is represented through ammonia stress rather than a separate NH3/NH4 calculation.
- Disease is modeled as risk and health decline rather than pathogen-specific transmission.
- Fish visuals are procedural stand-ins with species silhouettes and colors, not final biology-grade models.
- Compatibility is represented through parameter, group, territory, predation, and tank-size rules; a full pairwise behavioral matrix is future work.
