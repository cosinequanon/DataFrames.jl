##############################################################################
##
## PooledDataVector type definition
##
## An AbstractDataVector with efficient storage when values are repeated. A
## PDV wraps a vector of UInt8's, which are used to index into a compressed
## pool of values. NA's are 0's in the UInt vector.
##
## TODO: Make sure we don't overflow from refs being Uint16
## TODO: Allow ordering of factor levels
## TODO: Add metadata for dummy conversion
##
##############################################################################

type PooledDataVector{T} <: AbstractDataVector{T}
    refs::Vector{POOLED_DATA_VEC_REF_TYPE}
    pool::Vector{T}

    function PooledDataVector{T}(rs::Vector{POOLED_DATA_VEC_REF_TYPE},
                                 p::Vector{T})
        # refs mustn't overflow pool
        if max(rs) > length(p)
            error("Reference vector points beyond the end of the pool")
        end
        new(rs, p)
    end
end

##############################################################################
##
## PooledDataVector constructors
##
##############################################################################

# A no-op constructor
PooledDataVector(d::PooledDataVector) = d

# Echo inner constructor as an outer constructor
function PooledDataVector{T}(refs::Vector{POOLED_DATA_VEC_REF_TYPE},
                             pool::Vector{T})
    PooledDataVector{T}(refs, pool)
end

# How do you construct a PooledDataVector from a Vector?
# From the same sigs as a DataVector!
# Algorithm:
# * Start with:
#   * A null pool
#   * A pre-allocated refs
#   * A hash from T to Int
# * Iterate over d
#   * If value of d in pool already, set the refs accordingly
#   * If value is new, add it to the pool, then set refs
function PooledDataVector{T}(d::Vector{T}, m::AbstractVector{Bool})
    newrefs = Array(POOLED_DATA_VEC_REF_TYPE, length(d))
    newpool = Array(T, 0)
    poolref = Dict{T, POOLED_DATA_VEC_REF_TYPE}(0) # Why isn't this a set?
    maxref = 0

    # Loop through once to fill the poolref dict
    for i = 1:length(d)
        if !m[i]
            poolref[d[i]] = 0
        end
    end

    # Fill positions in poolref
    newpool = sort(keys(poolref))
    i = 1
    for p in newpool
        poolref[p] = i
        i += 1
    end

    # Fill in newrefs
    for i = 1:length(d)
        if m[i]
            newrefs[i] = 0
        else
            newrefs[i] = poolref[d[i]]
        end
    end

    return PooledDataVector(newrefs, newpool)
end

# Allow a pool to be provided by the user
function PooledDataVector{T}(d::Vector{T},
                             pool::Vector{T},
                             m::AbstractVector{Bool})
    if length(pool) > typemax(POOLED_DATA_VEC_REF_TYPE)
        error("Cannot construct a PooledDataVector with such a large pool")
    end

    newrefs = Array(POOLED_DATA_VEC_REF_TYPE, length(d))
    poolref = Dict{T, POOLED_DATA_VEC_REF_TYPE}(0)
    maxref = 0

    # loop through once to fill the poolref dict
    for i = 1:length(pool)
        poolref[pool[i]] = 0
    end

    # fill positions in poolref
    newpool = sort(keys(poolref))
    i = 1
    for p in newpool
        poolref[p] = i
        i += 1
    end

    # fill in newrefs
    for i = 1:length(d)
        if m[i]
            newrefs[i] = 0
        else
            if has(poolref, d[i])
              newrefs[i] = poolref[d[i]]
            else
              error("Vector contains elements not in provided pool")
            end
        end
    end

    return PooledDataVector(newrefs, newpool)
end

# Convert a BitVector to a Vector{Bool} w/ specified missingness
function PooledDataVector(d::BitVector, m::AbstractVector{Bool})
    PooledDataVector(convert(Vector{Bool}, d), m)
end

# Convert a DataVector to a PooledDataVector
PooledDataVector{T}(dv::DataVector{T}) = PooledDataVector(dv.data, dv.na)

# Convert a Vector{T} to a PooledDataVector
PooledDataVector{T}(x::Vector{T}) = PooledDataVector(x, falses(length(x)))

# Convert a BitVector to a Vector{Bool} w/o specified missingness
function PooledDataVector(x::BitVector)
    PooledDataVector(convert(Vector{Bool}, x), falses(length(x)))
end

# Explicitly convert Ranges into a PooledDataVector
PooledDataVector{T}(r::Ranges{T}) = PooledDataVector([r], falses(length(r)))

# Construct an all-NA PooledDataVector of a specific type
PooledDataVector(t::Type, n::Int) = PooledDataVector(Array(t, n), trues(n))

# Specify just a vector and a pool
function PooledDataVector{T}(d::Vector{T}, pool::Vector{T})
    PooledDataVector(d, pool, falses(length(d)))
end

# Initialized constructors with 0's, 1's
for (f, basef) in ((:pdatazeros, :zeros), (:pdataones, :ones))
    @eval begin
        ($f)(n::Int) = PooledDataVector(($basef)(n), falses(n))
        ($f)(t::Type, n::Int) = PooledDataVector(($basef)(t, n), falses(n))
    end
end

# Initialized constructors with false's or true's
for (f, basef) in ((:pdatafalses, :falses), (:pdatatrues, :trues))
    @eval begin
        ($f)(n::Int) = PooledDataVector(($basef)(n), falses(n))
    end
end

# Super hacked-out constructor: PooledDataVector[1, 2, 2, NA]
function ref(::Type{PooledDataVector}, vals...)
    # For now, just create a DataVector and then convert it
    # TODO: Rewrite for speed
    PooledDataVector(DataVector[vals...])
end

##############################################################################
##
## Basic size properties of all Data* objects
##
##############################################################################

size(v::PooledDataVector) = size(v.refs)
length(v::PooledDataVector) = length(v.refs)

##############################################################################
##
## Copying Data* objects
##
##############################################################################

copy(dv::PooledDataVector) = PooledDataVector(copy(dv.refs),
                                              copy(dv.pool))
# TODO: Implement copy_to()

##############################################################################
##
## Predicates, including the new isna()
##
##############################################################################

function isnan{T}(pdv::PooledDataVector{T})
    PooledDataVector(copy(pdv.refs), isnan(dv.pool))
end

function isfinite{T}(dv::PooledDataVector{T})
    PooledDataVector(copy(pdv.refs), isfinite(dv.pool))
end

isna(v::PooledDataVector) = v.refs .== 0

##############################################################################
##
## PooledDataVector utilities
##
## TODO: Add methods with these names for DataVector's
##       Decide whether levels() or unique() is primitive. Make the other
##       an alias.
##
##############################################################################

# Convert a PooledDataVector{T} to a DataVector{T}
function values{T}(x::PooledDataVector{T})
    n = length(x)
    res = DataArray(T, n)
    for i in 1:n
        r = x.refs[i]
        if r == 0
            res[i] = NA
        else
            res[i] = x.pool[r]
        end
    end
    return res
end
DataArray(pdv::PooledDataVector) = values(pdv)
values{T}(dv::DataVector{T}) = copy(dv)

function unique{T}(x::PooledDataVector{T})
    if any(x.refs .== 0)
        n = length(x.pool)
        d = Array(T, n + 1)
        for i in 1:n
            d[i] = x.pool[i]
        end
        m = falses(n + 1)
        m[n + 1] = true
        return DataArray(d, m)
    else
        return DataArray(copy(x.pool), falses(length(x.pool)))
    end
end
levels{T}(pdv::PooledDataVector{T}) = unique(pdv)

function unique{T}(adv::AbstractDataVector{T})
  values = Dict{Union(T, NAtype), Bool}()
  for i in 1:length(adv)
    values[adv[i]] = true
  end
  unique_values = keys(values)
  res = DataArray(T, length(unique_values))
  for i in 1:length(unique_values)
    res[i] = unique_values[i]
  end
  return res
end
levels{T}(adv::AbstractDataVector{T}) = unique(adv)

get_indices{T}(x::PooledDataVector{T}) = x.refs

function index_to_level{T}(x::PooledDataVector{T})
    d = Dict{POOLED_DATA_VEC_REF_TYPE, T}()
    for i in POOLED_DATA_VEC_REF_CONVERTER(1:length(x.pool))
        d[i] = x.pool[i]
    end
    return d
end

function level_to_index{T}(x::PooledDataVector{T})
    d = Dict{T, POOLED_DATA_VEC_REF_TYPE}()
    for i in POOLED_DATA_VEC_REF_CONVERTER(1:length(x.pool))
        d[x.pool[i]] = i
    end
    d
end

##############################################################################
##
## similar()
##
##############################################################################

function similar{T}(dv::PooledDataVector{T}, dim::Int)
    PooledDataVector(fill(uint16(0), dim), dv.pool)
end

function similar{T}(dv::PooledDataVector{T}, dims::Dims)
    PooledDataVector(fill(uint16(0), dims), dv.pool)
end

##############################################################################
##
## find()
##
##############################################################################

find(pdv::PooledDataVector{Bool}) = find(values(pdv))

##############################################################################
##
## ref()
##
##############################################################################

# dv[SingleItemIndex]
function ref(x::PooledDataVector, ind::Real)
    if x.refs[ind] == 0
        return NA
    else
        return x.pool[x.refs[ind]]
    end
end

# dv[MultiItemIndex]
function ref(x::PooledDataVector, inds::AbstractDataVector{Bool})
    inds = find(replaceNA(inds, false))
    return PooledDataVector(x.refs[inds], copy(x.pool))
end
function ref(x::PooledDataVector, inds::AbstractDataVector)
    inds = removeNA(inds)
    return PooledDataVector(x.refs[inds], copy(x.pool))
end
function ref(x::PooledDataVector, inds::Union(Vector, BitVector, Ranges))
    return PooledDataVector(x.refs[inds], copy(x.pool))
end

##############################################################################
##
## assign() definitions
##
##############################################################################

# x[SingleIndex] = NA
# TODO: Delete values from pool that no longer exist?
function assign(x::PooledDataVector, val::NAtype, ind::Real)
    x.refs[ind] = 0
    return NA
end

# x[SingleIndex] = Single Item
# TODO: Delete values from pool that no longer exist?
function assign(x::PooledDataVector, val::Any, ind::Real)
    val = convert(eltype(x), val)
    pool_idx = findfirst(x.pool, val)
    if pool_idx > 0
        x.refs[ind] = pool_idx
    else
        push!(x.pool, val)
        x.refs[ind] = length(x.pool)
    end
    return val
end

# x[MultiIndex] = NA
# TODO: Find a way to delete the next four methods
function assign(x::PooledDataVector{NAtype},
                val::NAtype,
                inds::AbstractVector{Bool})
    error("Don't use PooledDataVector{NAtype}'s")
end
function assign(x::PooledDataVector{NAtype},
                val::NAtype,
                inds::AbstractVector)
    error("Don't use PooledDataVector{NAtype}'s")
end

# x[MultiIndex] = NA
# TODO: Delete values from pool that no longer exist?
function assign(x::PooledDataVector, val::NAtype, inds::AbstractVector{Bool})
    inds = find(inds)
    x.refs[inds] = 0
    return NA
end
function assign(x::PooledDataVector, val::NAtype, inds::AbstractVector)
    x.refs[inds] = 0
    return NA
end

##############################################################################
##
## show() and similar methods
##
##############################################################################

function show{T}(io, x::PooledDataVector{T})
    print("values: ")
    print(values(x))
    print("\n")
    print("levels: ")
    print(levels(x))
end

function repl_show{T}(io::IO, dv::PooledDataVector{T})
    n = length(dv)
    print(io, "$n-element $T PooledDataVector\n")
    if n == 0
        return
    end
    max_lines = tty_rows() - 5
    head_lim = fld(max_lines, 2)
    if mod(max_lines, 2) == 0
        tail_lim = (n - fld(max_lines, 2)) + 2
    else
        tail_lim = (n - fld(max_lines, 2)) + 1
    end
    if n > max_lines
        for i in 1:head_lim
            println(io, strcat(' ', dv[i]))
        end
        println(io, " \u22ee")
        for i in tail_lim:(n - 1)
            println(io, strcat(' ', dv[i]))
        end
        println(io, strcat(' ', dv[n]))
    else
        for i in 1:(n - 1)
            println(io, strcat(' ', dv[i]))
        end
        println(io, strcat(' ', dv[n]))
    end
    print(io, "levels: ")
    print(io, levels(dv))
end

##############################################################################
##
## Replacement operations
##
##############################################################################

function replace!(x::PooledDataVector{NAtype}, fromval::NAtype, toval::NAtype)
    NA # no-op to deal with warning
end
function replace!{R}(x::PooledDataVector{R}, fromval::NAtype, toval::NAtype)
    NA # no-op to deal with warning
end
function replace!{S, T}(x::PooledDataVector{S}, fromval::T, toval::NAtype)
    fromidx = findfirst(x.pool, fromval)
    if fromidx == 0
        error("can't replace a value not in the pool in a PooledDataVector!")
    end

    x.refs[x.refs .== fromidx] = 0

    return NA
end
function replace!{S, T}(x::PooledDataVector{S}, fromval::NAtype, toval::T)
    toidx = findfirst(x.pool, toval)
    # if toval is in the pool, just do the assignment
    if toidx != 0
        x.refs[x.refs .== 0] = toidx
    else
        # otherwise, toval is new, add it to the pool
        push!(x.pool, toval)
        x.refs[x.refs .== 0] = length(x.pool)
    end

    return toval
end
function replace!{R, S, T}(x::PooledDataVector{R}, fromval::S, toval::T)
    # throw error if fromval isn't in the pool
    fromidx = findfirst(x.pool, fromval)
    if fromidx == 0
        error("can't replace a value not in the pool in a PooledDataVector!")
    end

    # if toval is in the pool too, use that and remove fromval from the pool
    toidx = findfirst(x.pool, toval)
    if toidx != 0
        x.refs[x.refs .== fromidx] = toidx
        #x.pool[fromidx] = None    TODO: what to do here??
    else
        # otherwise, toval is new, swap it in
        x.pool[fromidx] = toval
    end

    return toval
end

##############################################################################
##
## Sorting
##
## TODO: Remove
##
##############################################################################

sort(pd::PooledDataVector) = pd[order(pd)]
order(pd::PooledDataVector) = groupsort_indexer(pd)[1]

##############################################################################
##
## PooledDataVecs: EXPLANATION SHOULD GO HERE
##
##############################################################################

function PooledDataVecs{S, T}(v1::AbstractDataVector{S},
                              v2::AbstractDataVector{T})
    ## Return two PooledDataVecs that share the same pool.

    refs1 = Array(POOLED_DATA_VEC_REF_TYPE, length(v1))
    refs2 = Array(POOLED_DATA_VEC_REF_TYPE, length(v2))
    poolref = Dict{T,POOLED_DATA_VEC_REF_TYPE}(length(v1))
    maxref = 0

    # loop through once to fill the poolref dict
    for i = 1:length(v1)
        ## TODO see if we really need the NA checking here.
        ## if !isna(v1[i])
            poolref[v1[i]] = 0
        ## end
    end
    for i = 1:length(v2)
        ## if !isna(v2[i])
            poolref[v2[i]] = 0
        ## end
    end

    # fill positions in poolref
    pool = sort(keys(poolref))
    i = 1
    for p in pool
        poolref[p] = i
        i += 1
    end

    # fill in newrefs
    for i = 1:length(v1)
        ## if isna(v1[i])
        ##     refs1[i] = 0
        ## else
            refs1[i] = poolref[v1[i]]
        ## end
    end
    for i = 1:length(v2)
        ## if isna(v2[i])
        ##     refs2[i] = 0
        ## else
            refs2[i] = poolref[v2[i]]
        ## end
    end
    (PooledDataVector(refs1, pool),
     PooledDataVector(refs2, pool))
end