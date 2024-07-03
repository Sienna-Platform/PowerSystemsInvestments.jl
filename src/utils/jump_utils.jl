"""
Returns the correct container specification for the selected type of JuMP Model
"""
function container_spec(::Type{Float64}, axs...)
    cont = DenseAxisArray{Float64}(undef, axs...)
    cont.data .= fill(NaN, size(cont.data))
    return cont
end
