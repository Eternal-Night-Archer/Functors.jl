# Note that the argument f is not actually used in this method.
# See issue #62 for a discussion on how best to remove it.
function fmap(walk::AbstractWalk, f, x, ys...)
  # This avoids a performance penalty for recursive constructs in an anonymous function.
  # See Julia issue #47760 and Functors.jl issue #59.
  recurse(xs...) = walk(var"#self#", xs...)
  walk(recurse, x, ys...)
end

function fmap(f, x, ys...; exclude = isleaf,
                           walk = DefaultWalk(),
                           cache = IdDict(),
                           prune = NoKeyword())
  _walk = ExcludeWalk(AnonymousWalk(walk), f, exclude)
  if !isnothing(cache)
    _walk = CachedWalk(_walk, prune, cache)
  end
  fmap(_walk, f, x, ys...)
end

fmapstructure(f, x; kwargs...) = fmap(f, x; walk = StructuralWalk(), kwargs...)

fcollect(x; exclude = v -> false) =
  fmap(ExcludeWalk(CollectWalk(), _ -> nothing, exclude), _ -> nothing, x)
