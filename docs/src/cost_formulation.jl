### A Pluto.jl notebook ###
# v0.20.17

using Markdown
using InteractiveUtils

# ╔═╡ 51d50106-882f-11f0-23b1-5709adac6342
md"""
# Cost Formulations

This notebook describes the formulation of capital and operational costs used in the optimization models in `PowerSystemsInvestments.jl`.

## Capital Cost Formulation
$$\text{Amortization} = \frac{1 - (1 + d)^{-\text{CRP}}}{d}$$
$$\text{Capital Recovery Factor (CRF)} = \frac{r}{1 - (1 + r)^{-\text{CRP}}}$$

where $\text{CRP}$ is capital recovery period, $d$ is discount rate, and $r$ is interest rate.

$$\text{OC}_{\text{base year}} = \text{OC}_{\text{tech base year}} * {(1+i)}^{-(\text{tech base year} - \text{base year})}$$
where $\text{OC}$ is overnight costs, and $i$ is inflation rate. 

$$\text{Amortized OC}|_{\text{base year}} = \text{OC}_{\text{base year}} * \text{Amortization} * \text{CRF}$$

The annualized capital expenditure is:

$$\text{Net Present Value}|_{t} = \text{Amortized OC} * p * ({1 + d})^{-(st_p - \text{base year})}$$

t is beginning of investment period, and p is the investment time period.

## Fixed OM Cost (\$/kW-year in ATB)
"""


# ╔═╡ 39df9740-3fb5-497d-a288-0d6b0416ed04
md"""

SWITCH formulation

$$OC_{\text{t, base}} = \text{OC}_{\text{tech base year}} * {(1+i)}^{-(\text{tech base year} - \text{base year})}$$
$$OC_{p} = \sum_{t \in p}{OC_{\text{t, base}} * CRF}$$
$$\text{Annualized Cost}_{p} = OC_{p}  * \text{DF}$$

where 

$$\text{DF} = \text{Amortization} * \text{FPV} = \left(\frac{1 - (1 + d)^{-\text{CRP}}}{d}\right) * ({1 + d})^{-(st_p - \text{base year})}$$
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.11.2"
manifest_format = "2.0"
project_hash = "da39a3ee5e6b4b0d3255bfef95601890afd80709"

[deps]
"""

# ╔═╡ Cell order:
# ╠═51d50106-882f-11f0-23b1-5709adac6342
# ╠═39df9740-3fb5-497d-a288-0d6b0416ed04
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
