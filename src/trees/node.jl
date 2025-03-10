
"""
    Node

A Node represents a decision in the Tree.
It is a leaf with a prediction or has exactly one true and one false child and a decision
function.
"""
mutable struct Node{T<:Union{Real, String}}
    # Reference to whole dataset governed by the tree (This is not a copy as julia doesn't copy but only binds new aliases to the same object)
    # data points are rows, data features are columns
    dataset::Union{AbstractMatrix, Nothing}
    # labels can be categorical => String or numerical => Real
    labels::Union{AbstractVector{T}, Nothing}
    # Indices of the data in the dataset being governed by this node
    node_data::Vector{Int64}
    depth::Int64

    decision::Union{Decision, Nothing} #returns True -> go to right child else left
    decision_string::Union{String, Nothing} # *Optional* string for printing

    true_child::Union{Node, Nothing} #decision is True
    false_child::Union{Node, Nothing} #decision is NOT true
    prediction::Union{T, Nothing} # for leaves
    classify::Bool

    # Constructor handling assignments & splitting
    function Node(dataset::AbstractMatrix, labels::AbstractVector{T}, node_data::Vector{Int64}, classify::Bool, splitting_criterion::Function; depth=0, min_purity_gain=nothing, max_depth=0) where {T}
        N = new{T}(dataset, labels, node_data)
        N.depth = depth
        N.true_child = nothing
        N.false_child = nothing

        # Determine the best prediction in this node if it is/were a leaf node
        # (We calculate the prediction even in non-leaf nodes, because we need it to decide whether to split this node. This is because we also consider how much purity is gained by splitting this node.)
        if classify
            # in classification, we simply choose the most frequent label as our prediction
            N.prediction = most_frequent_class(labels, node_data)
        else
            # in regression, we choose the mean as our prediction as it minimizes the square loss
            N.prediction = label_mean(labels, node_data)
        end

        N.classify = classify

        N.decision, splitting_gain = split(N, splitting_criterion)
        if should_split(N, splitting_gain, max_depth)
            # Partition dataset into true/false datasets & pass them to the children
            true_data, false_data = split_indices(N.dataset, N.node_data, N.decision.fn, N.decision.param, N.decision.feature)
            N.true_child = Node(dataset, labels, true_data, classify, splitting_criterion, depth=N.depth+1, min_purity_gain=min_purity_gain, max_depth=max_depth)
            N.false_child = Node(dataset, labels, false_data, classify, splitting_criterion, depth=N.depth+1, min_purity_gain=min_purity_gain, max_depth=max_depth)
            # NOTE: The reason it is set to nothing here atm, is because N.prediction being nothing is later used to identify non-leaf nodes.
            N.prediction = nothing
        else
            # Clear decision as we don't want to split
            N.decision = nothing
        end
        return N
    end
end

# Custom constructor for keyword arguments
function Node(dataset, labels, classify; splitting_criterion=nothing, column_data=false, node_data=nothing, max_depth=0)

    # This is meant for when initializing a matrix like [[] [] []]. Then the inner []'s are inserted into the matrix as column vectors.
    # But since we would like them to be interpreted as row-vectors, we provide the option to transpose in this case.
    if column_data == true
        dataset = copy(transpose(dataset))
    end
    # if no subset was passed
    if isnothing(node_data)
        node_data = collect(1:size(dataset, 1))
    end
    if isnothing(splitting_criterion)
        if classify
            splitting_criterion = gini_gain
        else
            splitting_criterion = variance_gain
        end
    end
    return Node(dataset, labels, node_data, classify, splitting_criterion, max_depth=max_depth)
end

"""
    is_leaf(node::Node)::Bool

Do you seriously expect a description for this?
"""
function is_leaf(node::Node)::Bool
    return !isnothing(node.prediction)
end

"""
    _node_to_string(node::Node, is_true_child::Bool, indentation::String)

Recursive helper function to stringify the decision tree structure.

# Arguments

- `node::Node`: The current node to print.
- `is_true_child::Bool`: Boolean indicating if the node is a true branch child.
- `indentation::String`: The current indentation.
"""
function _node_to_string(node::Union{Node, Nothing}, is_true_child::Bool, indentation::String)
    if is_true_child
        prefix = indentation * "├─ True: "
    else
        prefix = indentation * "└─ False:"
    end

    if isnothing(node)
        return "$(prefix) <Nothing>\n"
    end
    if is_leaf(node)
        return "$(prefix) $(node.prediction)\n"
    end

    result = "$(prefix) $(node.decision) ?\n"
    if is_true_child
        indentation = indentation * "│  "
    else
        indentation = indentation * "   "
    end
    result *= _node_to_string(node.true_child, true, indentation)
    result *= _node_to_string(node.false_child, false, indentation)
    return result
end

"""
    _node_to_string_as_root(node::Node)

Print the tree from the given node by considering it to be the root of the tree.
"""
function _node_to_string_as_root(node::Node)
    if is_leaf(node)
        return "\nPrediction: $(node.prediction)\n"
    end

    result = "\n$(node.decision) ?\n"
    result *= _node_to_string(node.true_child, true, "")
    result *= _node_to_string(node.false_child, false, "")
    return result
end

function Base.show(io::IO, node::Node)
    print(io, _node_to_string_as_root(node))
end