
using Functors: functor, usecache

struct Foo; x; y; end
@functor Foo

struct Bar{T}; x::T; end
@functor Bar

struct OneChild3; x; y; z; end
@functor OneChild3 (y,)

struct NoChildren2; x; y; end

struct NoChild{T}; x::T; end


###
### Basic functionality
###

@testset "Children and Leaves" begin
  no_children = NoChildren2(1, 2)
  has_children = Foo(1, 2)
  @test Functors.isleaf(no_children)
  @test !Functors.isleaf(has_children)
  @test Functors.children(no_children) === Functors.NoChildren()
  @test Functors.children(has_children) == (x=1, y=2)
end

@testset "Nested" begin
  model = Bar(Foo(1, [1, 2, 3]))

  model′ = fmap(float, model)

  @test model.x.y == model′.x.y
  @test model′.x.y isa Vector{Float64}
end

@testset "Exclude" begin
  f(x::AbstractArray) = x
  f(x::Char) = 'z'

  x = ['a', 'b', 'c']
  @test fmap(f, x)  == ['z', 'z', 'z']
  @test fmap(f, x; exclude = x -> x isa AbstractArray) == x

  x = (['a', 'b', 'c'], ['d', 'e', 'f'])
  @test fmap(f, x)  == (['z', 'z', 'z'], ['z', 'z', 'z'])
  @test fmap(f, x; exclude = x -> x isa AbstractArray) == x
end

@testset "Property list" begin
  model = OneChild3(1, 2, 3)
  model′ = fmap(x -> 2x, model)

  @test (model′.x, model′.y, model′.z) == (1, 4, 3)
end

@testset "Sharing" begin
  shared = [1,2,3]
  m1 = Foo(shared, Foo([1,2,3], Foo(shared, [1,2,3])))
  m1f = fmap(float, m1)
  @test m1f.x === m1f.y.y.x
  @test m1f.x !== m1f.y.x
  m1p = fmapstructure(identity, m1; prune = nothing)
  @test m1p == (x = [1, 2, 3], y = (x = [1, 2, 3], y = (x = nothing, y = [1, 2, 3])))
  m1no = fmap(float, m1; cache = nothing)  # disable the cache by hand
  @test m1no.x !== m1no.y.y.x

  # Here "4" is not shared, because Foo isn't leaf:
  m2 = Foo(Foo(shared, 4), Foo(shared, 4))
  @test m2.x === m2.y
  m2f = fmap(float, m2)
  @test m2f.x.x === m2f.y.x
  m2p = fmapstructure(identity, m2; prune = Bar(0))
  @test m2p == (x = (x = [1, 2, 3], y = 4), y = (x = Bar{Int64}(0), y = 4))

  # Repeated isbits types should not automatically be regarded as shared:
  m3 = Foo(Foo(shared, 1:3), Foo(1:3, shared))
  m3p = fmapstructure(identity, m3; prune = 0)
  @test m3p.y.y == 0
  @test m3p.y.x == 1:3

  # All-isbits trees need not create a cache at all:
  m4 = (x=1, y=(2, 3), z=4:5)
  @test isbits(fmap(float, m4))
  @test_skip 0 == @allocated fmap(float, m4)  # true, but fails in tests

  # Shared mutable containers are preserved, even if all children are isbits:
  ref = Ref(1)
  m5 = (x = ref, y = ref, z = Ref(1))
  m5f = fmap(x -> x/2, m5)
  @test m5f.x === m5f.y
  @test m5f.x !== m5f.z

  @testset "usecache ($d)" for d in [IdDict(), Base.IdSet()]
    # Leaf types:
    @test usecache(d, [1,2])
    @test !usecache(d, 4.0)
    @test usecache(d, NoChild([1,2]))
    @test !usecache(d, NoChild((3,4)))

    # Not leaf:
    @test usecache(d, Ref(3))  # mutable container
    @test !usecache(d, (5, 6.0))
    @test !usecache(d, (a = 2pi, b = missing))

    @test !usecache(d, (5, [6.0]'))  # contains mutable
    @test !usecache(d, (x = [1,2,3], y = 4))

    usecache(d, OneChild3([1,2], 3, nothing))  # mutable isn't a child, do we care?

    # No dictionary:
    @test !usecache(nothing, [1,2])
    @test !usecache(nothing, 3)
  end
end

@testset "functor(typeof(x), y) from @functor" begin
  nt1, re1 = functor(Foo, (x=1, y=2, z=3))
  @test nt1 == (x = 1, y = 2)
  @test re1((x = 10, y = 20)) == Foo(10, 20)
  re1((y = 22, x = 11)) # gives Foo(22, 11), is that a bug?

  nt2, re2 = functor(Foo, (z=33, x=1, y=2))
  @test nt2 == (x = 1, y = 2)
  @test re2((x = 10, y = 20)) == Foo(10, 20)

  @test_throws Exception functor(Foo, (z=33, x=1))  # type NamedTuple has no field y

  nt3, re3 = functor(OneChild3, (x=1, y=2, z=3))
  @test nt3 == (y = 2,)
  @test re3((y = 20,)) == OneChild3(1, 20, 3)
  re3(22) # gives OneChild3(1, 22, 3), is that a bug?
end

@testset "functor(typeof(x), y) for Base types" begin
  nt11, re11 = functor(NamedTuple{(:x, :y)}, (x=1, y=2, z=3))
  @test nt11 == (x = 1, y = 2)
  @test re11((x = 10, y = 20)) == (x = 10, y = 20)
  re11((y = 22, x = 11))
  re11((11, 22))  # passes right through

  nt12, re12 = functor(NamedTuple{(:x, :y)}, (z=33, x=1, y=2))
  @test nt12 == (x = 1, y = 2)
  @test re12((x = 10, y = 20)) == (x = 10, y = 20)

  @test_throws Exception functor(NamedTuple{(:x, :y)}, (z=33, x=1))
end

###
### Extras
###

@testset "Walk" begin
  model = Foo((0, Bar([1, 2, 3])), [4, 5])

  model′ = fmapstructure(identity, model)
  @test model′ == (; x=(0, (; x=[1, 2, 3])), y=[4, 5])
end

@testset "fcollect" begin
  m1 = [1, 2, 3]
  m2 = 1
  m3 = Foo(m1, m2)
  m4 = Bar(m3)
  @test all(fcollect(m4) .=== [m4, m3, m1, m2])
  @test all(fcollect(m4, exclude = x -> x isa Array) .=== [m4, m3, m2])
  @test all(fcollect(m4, exclude = x -> x isa Foo) .=== [m4])

  m1 = [1, 2, 3]
  m2 = Bar(m1)
  m0 = NoChildren2(:a, :b)
  m3 = Foo(m2, m0)
  m4 = Bar(m3)
  @test all(fcollect(m4) .=== [m4, m3, m2, m1, m0])

  m1 = [1, 2, 3]
  m2 = [1, 2, 3]
  m3 = Foo(m1, m2)
  @test all(fcollect(m3) .=== [m3, m1, m2])

  m1 = [1, 2, 3]
  m2 = SVector{length(m1)}(m1)
  m2′ = SVector{length(m1)}(m1)
  m3 = Foo(m1, m1)
  m4 = Foo(m2, m2′)
  @test all(fcollect(m3) .=== [m3, m1])
  @test all(fcollect(m4) .=== [m4, m2, m2′])
end

###
### Vararg forms
###

@testset "fmap(f, x, y)" begin
  m1 = (x = [1,2], y = 3)
  n1 = (x = [4,5], y = 6)
  @test fmap(+, m1, n1) == (x = [5, 7], y = 9)

  # Reconstruction type comes from the first argument
  foo1 = Foo([7,8], 9)
  @test fmap(+, m1, foo1) == (x = [8, 10], y = 12)
  @test fmap(+, foo1, n1) isa Foo
  @test fmap(+, foo1, n1).x == [11, 13]

  # Mismatched trees should be an error
  m2 = (x = [1,2], y = (a = [3,4], b = 5))
  n2 = (x = [6,7], y = 8)
  @test_throws Exception fmap(first∘tuple, m2, n2)  # ERROR: type Int64 has no field a
  @test_throws Exception fmap(first∘tuple, m2, n2)

  # The cache uses IDs from the first argument
  shared = [1,2,3]
  m3 = (x = shared, y = [4,5,6], z = shared)
  n3 = (x = shared, y = shared, z = [7,8,9])
  @test fmap(+, m3, n3) == (x = [2, 4, 6], y = [5, 7, 9], z = [2, 4, 6])
  z3 = fmap(+, m3, n3)
  @test z3.x === z3.z

  # Pruning of duplicates:
  @test fmap(+, m3, n3; prune = nothing) == (x = [2,4,6], y = [5,7,9], z = nothing)

  # More than two arguments:
  z4 = fmap(+, m3, n3, m3, n3)
  @test z4 == fmap(x -> 2x, z3)
  @test z4.x === z4.z

  @test fmap(+, foo1, m1, n1) isa Foo
  @static if VERSION >= v"1.6" # fails on Julia 1.0
    @test fmap(.*, m1, foo1, n1) == (x = [4*7, 2*5*8], y = 3*6*9)
  end
end

@testset "old test update.jl" begin
  struct M{F,T,S}
    σ::F
    W::T
    b::S
  end

  @functor M

  (m::M)(x) = m.σ.(m.W * x .+ m.b)

  m = M(identity, ones(Float32, 3, 4), zeros(Float32, 3))
  x = ones(Float32, 4, 2)
  m̄, _ = gradient((m,x) -> sum(m(x)), m, x)
  m̂ = Functors.fmap(m, m̄) do x, y
    isnothing(x) && return y
    isnothing(y) && return x
    x .- 0.1f0 .* y
  end

  @test m̂.W ≈ fill(0.8f0, size(m.W))
  @test m̂.b ≈ fill(-0.2f0, size(m.b))
end

###
### FlexibleFunctors.jl
###

struct FFoo
  x
  y
  p
end
@flexiblefunctor FFoo p

struct FBar
  x
  p
end
@flexiblefunctor FBar p

struct FOneChild4
  x
  y
  z
  p
end
@flexiblefunctor FOneChild4 p

@testset "Flexible Nested" begin
  model = FBar(FFoo(1, [1, 2, 3], (:y, )), (:x,))

  model′ = fmap(float, model)

  @test model.x.y == model′.x.y
  @test model′.x.y isa Vector{Float64}
end

@testset "Flexible Walk" begin
  model = FFoo((0, FBar([1, 2, 3], (:x,))), [4, 5], (:x, :y))

  model′ = fmapstructure(identity, model)
  @test model′ == (; x=(0, (; x=[1, 2, 3])), y=[4, 5])

  model2 = FFoo((0, FBar([1, 2, 3], (:x,))), [4, 5], (:x,))

  model2′ = fmapstructure(identity, model2)
  @test model2′ == (; x=(0, (; x=[1, 2, 3])))
end

@testset "Flexible Property list" begin
  model = FOneChild4(1, 2, 3, (:x, :z))
  model′ = fmap(x -> 2x, model)

  @test (model′.x, model′.y, model′.z) == (2, 2, 6)
end

@testset "Flexible fcollect" begin
  m1 = 1
  m2 = [1, 2, 3]
  m3 = FFoo(m1, m2, (:y, ))
  m4 = FBar(m3, (:x,))
  @test all(fcollect(m4) .=== [m4, m3, m2])
  @test all(fcollect(m4, exclude = x -> x isa Array) .=== [m4, m3])
  @test all(fcollect(m4, exclude = x -> x isa FFoo) .=== [m4])

  m0 = NoChildren2(:a, :b)
  m1 = [1, 2, 3]
  m2 = FBar(m1, ())
  m3 = FFoo(m2, m0, (:x, :y,))
  m4 = FBar(m3, (:x,))
  @test all(fcollect(m4) .=== [m4, m3, m2, m0])
end

@testset "Dict" begin
  d = Dict(:a => 1, :b => 2)
  
  @test Functors.children(d) == d
  @test fmap(x -> x + 1, d) == Dict(:a => 2, :b => 3)

  d = Dict(:a => 1, :b => Dict("a" => 5, "b" => 6, "c" => 7))  
  @test Functors.children(d) == d
  @test fmap(x -> x + 1, d) == Dict(:a => 2, :b => Dict("a" => 6, "b" => 7, "c" => 8))

  @testset "fmap(+, x, y)" begin
    m1 = Dict("x" => [1,2], "y" => 3)
    n1 = Dict("x" => [4,5], "y" => 6)
    @test fmap(+, m1, n1) == Dict("x" => [5, 7], "y" => 9)
    
    m1 = Dict(:x => [1,2], :y => 3)
    n1 = (x = [4,5], y = 6)
    @test fmap(+, m1, n1) == Dict(:x => [5, 7], :y => 9)

    # extra keys in n1 are ignored
    m1 = Dict("x" => [1,2], "y" => Dict(:a => 3, :b => 4))
    n1 = Dict("x" => [4,5], "y" => Dict(:a => 0.1, :b => 0.2, :c => 5), "z" => Dict(:a => 5))
    @test fmap(+, m1, n1) == Dict("x" => [5, 7], "y" => Dict(:a=>3.1, :b=>4.2))
  end
end

@testset "@leaf" begin
  struct A; x; end
  @functor A
  a = A(1)
  @test Functors.children(a) === (x = 1,)
  Functors.@leaf A
  children, re = Functors.functor(a)
  @test children == Functors.NoChildren() 
  @test re(children) === a
end

@testset "IterateWalk" begin
    x = ([1, 2, 3], 4, (5, 6, [7, 8]));
    make_iterator(x) = x isa AbstractVector ? x.^2 : (x^2,);
    iter = fmap(make_iterator, x; walk=Functors.IterateWalk(), cache=nothing);
    @test iter isa Iterators.Flatten
    @test collect(iter) == [1, 2, 3, 4, 5, 6, 7, 8].^2

    # Test iteration of multiple trees together
    y = ([8, 7, 6], 5, (4, 3, [2, 1]));
    make_zipped_iterator(x, y) = zip(make_iterator(x), make_iterator(y));
    zipped_iter = fmap(make_zipped_iterator, x, y; walk=Functors.IterateWalk(), cache=nothing);
    @test zipped_iter isa Iterators.Flatten
    @test collect(zipped_iter) == collect(Iterators.zip([1, 2, 3, 4, 5, 6, 7, 8].^2, [8, 7, 6, 5, 4, 3, 2, 1].^2))
end
