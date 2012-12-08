
#   Debug.Flow:
# =============
# Flow control for interactive debug trap

module Flow
using Base, Meta, AST, Runtime, Graft, Eval
import AST.is_emittable, Base.isequal
export @bp, BPNode, DBState
export continue!, singlestep!, stepover!, stepout!


## BreakPoint ##
type BreakPoint; end
typealias BPNode Node{BreakPoint}
is_emittable(::BPNode) = false

macro bp()
    Node(BreakPoint())
end

is_trap(::BPNode)   = true
is_trap(::Event)    = true
is_trap(node::Node) = is_evaluable(node) && isblocknode(parentof(node))

instrument(trap_ex, ex) = Graft.instrument(is_trap, trap_ex, ex)


## Cond ##
abstract Cond

type Continue   <: Cond; end
type SingleStep <: Cond; end

type ContinueInside <: Cond; frame::Frame; outside::Cond; end
type StepOver       <: Cond; end

does_trap(::SingleStep)     = true
does_trap(::Continue)       = false
does_trap(::ContinueInside) = false
does_trap(::StepOver)       = true

leave(cond::ContinueInside, f::Frame) = (cond.frame == f ? cond.outside : cond)

enter(cond::StepOver, frame::Frame) = ContinueInside(frame, cond)
leave(cond::StepOver, frame::Frame) = SingleStep()

enter(cond::Cond, ::Frame) = cond
leave(cond::Cond, ::Frame) = cond


## DBState ##
type DBState
    cond::Cond
    breakpoints::Set{Node}
    grafts::Dict{Node,Any}
    DBState() = new(Continue(), Set{Node}(), Dict{Node,Any}())
end

continue!(  s::DBState) = (s.cond = Continue())
singlestep!(s::DBState) = (s.cond = SingleStep())
stepover!(  s::DBState) = (s.cond = StepOver())
function stepout!(st::DBState, node::Node, s::Scope)
    st.cond = ContinueInside(enclosing_scope_frame(Frame(node,s)),SingleStep())
end

function trap(state::DBState, e::Enter, s::Scope)
    state.cond = enter(state.cond, Frame(e.node, s))
    false
end
function trap(state::DBState, e::Leave, s::Scope) 
    state.cond = leave(state.cond, Frame(e.node, s))
    false
end
function trap(state::DBState, n::Node, s::Scope)
    if isa(n, BPNode) || has(state.breakpoints, n); singlestep!(state); end
    if has(state.grafts, n)
        debug_eval(s, state.grafts[n])
    end
    does_trap(state.cond)    
end

end # module
