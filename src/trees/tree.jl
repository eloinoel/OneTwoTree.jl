#This File contains the fundamentals for decision trees in Julia

# ----------------------------------------------------------------
# MARK: Structs & Constructors
# ----------------------------------------------------------------

abstract type AbstractDecisionTree end

"""
    DecisionTreeClassifier <: AbstractDecisionTree

A DecisionTreeClassifier is a tree of decision nodes. It can predict classes based on the input data.
In addition to a root node it holds meta informations such as max_depth etc.
Use `fit(tree, features, labels)` to create a tree from data.
"""
mutable struct DecisionTreeClassifier <: AbstractDecisionTree
    root::Union{Node, Nothing}
    max_depth::Int
end

"""
    DecisionTreeClassifier(; root=nothing, max_depth=-1)

Initialises a decision tree model.

# Arguments

- `root::Union{Node, Nothing}`: the root node of the decision tree; `nothing` if the tree is empty
- `max_depth::Int`: maximum depth of the decision tree; no limit if equal to -1
"""
function DecisionTreeClassifier(; root::Union{Node, Nothing}=nothing, max_depth::Int=-1)
    if max_depth < -1
        throw(ArgumentError("DecisionTreeClassifier: Got invalid max_depth. Set it to a value >= -1. (-1 means unlimited depth)"))
    end
    DecisionTreeClassifier(root, max_depth)
end

"""
    DecisionTreeRegressor

A DecisionTreeRegressor is a tree of decision nodes. It can predict function values based on the input data.
In addition to a root node it holds meta informations such as max_depth etc.
Use `fit(tree, features, labels)` to create a tree from data.
"""
mutable struct DecisionTreeRegressor <: AbstractDecisionTree
    root::Union{Node, Nothing}
    max_depth::Int
end

"""
    DecisionTreeRegressor(; root=nothing, max_depth=-1)

Initialises a decision tree model.

# Arguments

- `root::Union{Node, Nothing}`: the root node of the decision tree; `nothing` if the tree is empty
- `max_depth::Int`: maximum depth of the decision tree; no limit if equal to -1
"""
function DecisionTreeRegressor(; root::Union{Node, Nothing}=nothing, max_depth::Int=-1)
    if max_depth < -1
        throw(ArgumentError("DecisionTreeRegressor: Got invalid max_depth. Set it to a value >= -1. (-1 means unlimited depth)"))
    end
    DecisionTreeRegressor(root, max_depth)
end



# ----------------------------------------------------------------
# MARK: Functions
# ----------------------------------------------------------------

"""
    _verify_fit!_args(tree, dataset, labels, column_data)

Some guards to ensure the input data is valid for training a tree.
"""
function _verify_fit!_args(tree, dataset, labels, column_data)
    if isempty(labels)
        throw(ArgumentError("fit!: Cannot build tree from empty label set."))
    end
    if isempty(dataset)
        throw(ArgumentError("fit!: Cannot build tree from empty dataset."))
    end
    if tree.max_depth < -1
        throw(ArgumentError("fit!: Cannot build tree with negative depth, but got max_depth=$(tree.max_depth)."))
    end
    if (!column_data && size(dataset, 1) != length(labels))
        throw(ArgumentError("fit!: Dimension mismatch! Number of datapoints $(size(dataset, 1)) != number of labels $(length(labels)).\n Maybe transposing your dataset matrix or setting column_data=true helps?"))
    end
    if (column_data && size(dataset, 2) != length(labels))
        throw(ArgumentError("fit!: Dimension mismatch! Number of datapoints $(size(dataset, 2)) != number of labels $(length(labels)).\n Maybe transposing your dataset matrix or setting column_data=false helps?"))
    end
    for label in labels
        if typeof(label) != typeof(labels[1])
            throw(ArgumentError("fit!: Encountered heterogeneous label types. Please make sure all labels are of the same type."))
        end
    end
    if tree isa DecisionTreeRegressor && (labels[1] isa String) # vorher: !(labels[1] isa String)
        throw(ArgumentError("Cannot train a DecisionTreeRegressor on a dataset with categorical labels."))
    end
end

"""
    fit!(tree::AbstractDecisionTree, features::AbstractMatrix{S}, labels::AbstractVector{T}; splitting_criterion=nothing, column_data=false) where {S, T<:Union{Real, String}}

Train a decision tree on the given data using some algorithm (e.g. CART).

# Arguments

- `tree::AbstractDecisionTree`: the tree to be trained
- `dataset::AbstractMatrix{S}`: the training data
- `labels::AbstractVector{T}`: the target labels
- `splitting_criterion::Function`: a function indicating some notion of gain from splitting a node. If not provided, default criteria for classification and regression are used.
- `column_data::Bool`: whether the datapoints are contained in dataset columnwise
(OneTwoTree provides the following splitting criteria for classification: gini_gain, information_gain; and for regression: variance_gain. If you'd like to define a splitting criterion yourself, you need to consider the following:

1. The function must calculate a 'gain'-value for a split of a node, meaning that larger values are considered better.
2. The function signature must conform to `my_func(parent_labels::AbstractVector, true_child_labels::AbstractVector, false_child_labels::AbstractVector)`,
where `parent_labels` is a set of datapoint labels, which is split into two subsets `true_child_labels` & `false_child_labels` by some discriminating function. (Each label in `parent_labels` is contained in exactly one of the two subsets.)
"""
function fit!(tree::AbstractDecisionTree, features::AbstractMatrix{S}, labels::AbstractVector{T}; splitting_criterion=nothing, column_data=false) where {S, T<:Union{Real, String}}
    _verify_fit!_args(tree, features, labels, column_data)

    classify = (tree isa DecisionTreeClassifier)
    if isnothing(splitting_criterion)
        if classify
            splitting_criterion = gini_gain
        else
            splitting_criterion = variance_gain
        end
    end
    tree.root = Node(features, labels, classify, splitting_criterion=splitting_criterion, max_depth=tree.max_depth, column_data=column_data)
end

"""
    predict(tree::AbstractDecisionTree, X::Union{AbstractMatrix, AbstractVector})

Traverses the tree for given datapoints and returns that trees prediction.

# Arguments

- `tree::AbstractDecisionTree`: the tree to predict with
- `X::Union{AbstractMatrix, AbstractVector}`: the data to predict on
"""
function predict(tree::AbstractDecisionTree, X::Union{AbstractMatrix, AbstractVector})
    if isnothing(tree.root)
        throw(ArgumentError("Cannot predict from an empty tree. Maybe you forgot to fit your model?"))
    end

    return predict(tree.root, X)
end

function predict(node::Node, datapoint::AbstractVector)
    if is_leaf(node)
        return node.prediction
    end

    if call(node.decision, datapoint)
        return predict(node.true_child, datapoint)
    else
        return predict(node.false_child, datapoint)
    end
end

function predict(node::Node, dataset::AbstractMatrix)
    if is_leaf(node)
        #println("Node prediction ist $(node.prediction)")
        return fill(node.prediction, size(dataset, 1))
        #return node.prediction * ones(size(dataset, 1))
    end

    result = []

    for i in range(1, size(dataset, 1))
        datapoint = dataset[i, :]
        if call(node.decision, datapoint)
            push!(result, predict(node.true_child, datapoint))
        else
            push!(result, predict(node.false_child, datapoint))
        end
    end
    return result
end

"""
    calc_accuracy(labels::AbstractArray, predictions::AbstractArray)

Calculates the accuracy of the predictions compared to the labels.
"""
function calc_accuracy(labels::AbstractArray, predictions::AbstractArray)
    if length(labels) != length(predictions)
        throw(ArgumentError("Length of labels and predictions must be equal."))
    end

    if length(labels) == 0
        return 0.0
    end

    correct = 0.0
    for i in eachindex(labels)
        if labels[i] == predictions[i]
            correct += 1.0
        end
    end

    return correct / length(labels)
end

"""
    calc_depth(tree::AbstractDecisionTree)

Traverses the tree and returns the maximum depth.
"""
function calc_depth(tree::AbstractDecisionTree)
    max_depth = 0
    if isnothing(tree.root)
        return max_depth
    end

    to_visit = [(tree.root, 0)]
    while !isempty(to_visit)
        node, cur_depth = popfirst!(to_visit)

        if cur_depth > max_depth
            max_depth = cur_depth
        end

        if !isnothing(node.true_child)
            push!(to_visit, (node.true_child, cur_depth + 1))
        end

        if !isnothing(node.false_child)
            push!(to_visit, (node.false_child, cur_depth + 1))
        end
    end
    return max_depth
end

#----------------------------------------
# MARK: Printing
#----------------------------------------

"""
    _tree_to_string(tree::AbstractDecisionTree, print_parameters=true)

Returns a textual visualization of the decision tree.

# Arguments

- `tree::AbstractDecisionTree` The `DecisionTree` instance to print.
- `print_parameters::Bool=true`: (Optional) Whether to print the tree parameters like `max_depth`.

# Example output:
```
x < 28.0 ?
├─ False: x == 161.0 ?
│  ├─ False: 842
│  └─ True: 2493
└─ True: 683
```
"""
function _tree_to_string(tree::AbstractDecisionTree, print_parameters=true)
    if isnothing(tree.root)
        return "\nTree(max_depth=$(tree.max_depth), root=nothing)\n"
    end

    result = ""
    if print_parameters
        result *= "Tree(max_depth=$(tree.max_depth))"
    end
    result *= _node_to_string_as_root(tree.root)
    return result
end

function Base.show(io::IO, tree::AbstractDecisionTree)
    print(io, _tree_to_string(tree))
end

"""
    print_tree(tree::AbstractDecisionTree; io::IO=stdout)

Returns a textual visualization of the decision tree.

# Arguments

- `tree::AbstractDecisionTree` The `DecisionTree` instance to print.
- `io::IO=stdout`: (Optional) The I/O stream for printing

# Example output:
```
x < 28.0 ?
├─ False: x == 161.0 ?
│  ├─ False: 842
│  └─ True: 2493
└─ True: 683
```
"""
function print_tree(tree::AbstractDecisionTree; io::IO=stdout)
    print(io, _tree_to_string(tree, false))
end
