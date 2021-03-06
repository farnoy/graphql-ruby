# frozen_string_literal: true
require "graphql/field/resolve"

module GraphQL
  # {Field}s belong to {ObjectType}s and {InterfaceType}s.
  #
  # They're usually created with the `field` helper. If you create it by hand, make sure {#name} is a String.
  #
  # A field must have a return type, but if you want to defer the return type calculation until later,
  # you can pass a proc for the return type. That proc will be called when the schema is defined.
  #
  # @example Lazy type resolution
  #   # If the field's type isn't defined yet, you can pass a proc
  #   field :city, -> { TypeForModelName.find("City") }
  #
  # For complex field definition, you can pass a block to the `field` helper, eg `field :name do ... end`.
  # This block is equivalent to calling `GraphQL::Field.define { ... }`.
  #
  # @example Defining a field with a block
  #   field :city, CityType do
  #     # field definition continues inside the block
  #   end
  #
  # ## Resolve
  #
  # Fields have `resolve` functions to determine their values at query-time.
  # The default implementation is to call a method on the object based on the field name.
  #
  # @example Create a field which calls a method with the same name.
  #   GraphQL::ObjectType.define do
  #     field :name, types.String, "The name of this thing "
  #   end
  #
  # You can specify a custom proc with the `resolve` helper.
  #
  # There are some shortcuts for common `resolve` implementations:
  #   - Provide `property:` to call a method with a different name than the field name
  #   - Provide `hash_key:` to resolve the field by doing a key lookup, eg `obj[:my_hash_key]`
  #
  # @example Create a field that calls a different method on the object
  #   GraphQL::ObjectType.define do
  #     # use the `property` keyword:
  #     field :firstName, types.String, property: :first_name
  #   end
  #
  # @example Create a field looks up with `[hash_key]`
  #   GraphQL::ObjectType.define do
  #     # use the `hash_key` keyword:
  #     field :firstName, types.String, hash_key: :first_name
  #   end
  #
  # ## Arguments
  #
  # Fields can take inputs; they're called arguments. You can define them with the `argument` helper.
  #
  # @example Create a field with an argument
  #   field :students, types[StudentType] do
  #     argument :grade, types.Int
  #     resolve ->(obj, args, ctx) {
  #       Student.where(grade: args[:grade])
  #     }
  #   end
  #
  # They can have default values which will be provided to `resolve` if the query doesn't include a value.
  #
  # @example Argument with a default value
  #   field :events, types[EventType] do
  #     # by default, don't include past events
  #     argument :includePast, types.Boolean, default_value: false
  #     resolve ->(obj, args, ctx) {
  #       args[:includePast] # => false if no value was provided in the query
  #       # ...
  #     }
  #   end
  #
  # Only certain types maybe used for inputs:
  #
  # - Scalars
  # - Enums
  # - Input Objects
  # - Lists of those types
  #
  # Input types may also be non-null -- in that case, the query will fail
  # if the input is not present.
  #
  # ## Complexity
  #
  # Fields can have _complexity_ values which describe the computation cost of resolving the field.
  # You can provide the complexity as a constant with `complexity:` or as a proc, with the `complexity` helper.
  #
  # @example Custom complexity values
  #   # Complexity can be a number or a proc.
  #
  #   # Complexity can be defined with a keyword:
  #   field :expensive_calculation, !types.Int, complexity: 10
  #
  #   # Or inside the block:
  #   field :expensive_calculation_2, !types.Int do
  #     complexity ->(ctx, args, child_complexity) { ctx[:current_user].staff? ? 0 : 10 }
  #   end
  #
  # @example Calculating the complexity of a list field
  #   field :items, types[ItemType] do
  #     argument :limit, !types.Int
  #     # Mulitply the child complexity by the possible items on the list
  #     complexity ->(ctx, args, child_complexity) { child_complexity * args[:limit] }
  #   end
  #
  # @example Creating a field, then assigning it to a type
  #   name_field = GraphQL::Field.define do
  #     name("Name")
  #     type(!types.String)
  #     description("The name of this thing")
  #     resolve ->(object, arguments, context) { object.name }
  #   end
  #
  #   NamedType = GraphQL::ObjectType.define do
  #     # The second argument may be a GraphQL::Field
  #     field :name, name_field
  #   end
  #
  class Field
    include GraphQL::Define::InstanceDefinable
    accepts_definitions :name, :description, :deprecation_reason,
      :resolve, :lazy_resolve,
      :type, :arguments,
      :property, :hash_key, :complexity, :mutation,
      :relay_node_field,
      :relay_nodes_field,
      argument: GraphQL::Define::AssignArgument

    ensure_defined(
      :name, :deprecation_reason, :description, :description=, :property, :hash_key, :mutation, :arguments, :complexity,
      :resolve, :resolve=, :lazy_resolve, :lazy_resolve=, :lazy_resolve_proc, :resolve_proc,
      :type, :type=, :name=, :property=, :hash_key=,
      :relay_node_field, :relay_nodes_field, :default_arguments
    )

    # @return [Boolean] True if this is the Relay find-by-id field
    attr_accessor :relay_node_field

    # @return [Boolean] True if this is the Relay find-by-ids field
    attr_accessor :relay_nodes_field

    # @return [<#call(obj, args, ctx)>] A proc-like object which can be called to return the field's value
    attr_reader :resolve_proc

    # @return [<#call(obj, args, ctx)>] A proc-like object which can be called trigger a lazy resolution
    attr_reader :lazy_resolve_proc

    # @return [String] The name of this field on its {GraphQL::ObjectType} (or {GraphQL::InterfaceType})
    attr_accessor :name

    # @return [String, nil] The client-facing description of this field
    attr_accessor :description

    # @return [String, nil] The client-facing reason why this field is deprecated (if present, the field is deprecated)
    attr_accessor :deprecation_reason

    # @return [Hash<String => GraphQL::Argument>] Map String argument names to their {GraphQL::Argument} implementations
    attr_accessor :arguments

    # @return [GraphQL::Relay::Mutation, nil] The mutation this field was derived from, if it was derived from a mutation
    attr_accessor :mutation

    # @return [Numeric, Proc] The complexity for this field (default: 1), as a constant or a proc like `->(query_ctx, args, child_complexity) { } # Numeric`
    attr_accessor :complexity

    # @return [Symbol, nil] The method to call on `obj` to return this field (overrides {#name} if present)
    attr_accessor :property

    # @return [Object, nil] The key to access with `obj.[]` to resolve this field (overrides {#name} if present)
    attr_accessor :hash_key

    def initialize
      @complexity = 1
      @arguments = {}
      @resolve_proc = build_default_resolver
      @lazy_resolve_proc = DefaultLazyResolve
      @relay_node_field = false
      @default_arguments = nil
    end

    def initialize_copy(other)
      super
      @arguments = other.arguments.dup
      @default_arguments = nil
    end

    # Get a value for this field
    # @example resolving a field value
    #   field.resolve(obj, args, ctx)
    #
    # @param object [Object] The object this field belongs to
    # @param arguments [Hash] Arguments declared in the query
    # @param context [GraphQL::Query::Context]
    def resolve(object, arguments, context)
      resolve_proc.call(object, arguments, context)
    end

    # Provide a new callable for this field's resolve function. If `nil`,
    # a new resolve proc will be build based on its {#name}, {#property} or {#hash_key}.
    # @param new_resolve_proc [<#call(obj, args, ctx)>, nil]
    def resolve=(new_resolve_proc)
      @resolve_proc = new_resolve_proc || build_default_resolver
    end

    def type=(new_return_type)
      @clean_type = nil
      @dirty_type = new_return_type
    end

    # Get the return type for this field.
    def type
      @clean_type ||= GraphQL::BaseType.resolve_related_type(@dirty_type)
    end

    # You can only set a field's name _once_ -- this to prevent
    # passing the same {Field} to multiple `.field` calls.
    #
    # This is important because {#name} may be used by {#resolve}.
    def name=(new_name)
      if @name.nil?
        @name = new_name
      elsif @name != new_name
        raise("Can't rename an already-named field. (Tried to rename \"#{@name}\" to \"#{new_name}\".) If you're passing a field with the `field:` argument, make sure it's an unused instance of GraphQL::Field.")
      end
    end

    # @param new_property [Symbol] A method to call to resolve this field. Overrides the existing resolve proc.
    def property=(new_property)
      @property = new_property
      self.resolve = nil # reset resolve proc
    end

    # @param new_hash_key [Symbol] A key to access with `#[key]` to resolve this field. Overrides the existing resolve proc.
    def hash_key=(new_hash_key)
      @hash_key = new_hash_key
      self.resolve = nil # reset resolve proc
    end

    def to_s
      "<Field name:#{name || "not-named"} desc:#{description} resolve:#{resolve_proc}>"
    end

    # If {#resolve} returned and object which should be handled lazily,
    # this method will be called later force the object to return its value.
    # @param obj [Object] The {#resolve}-provided object, registered with {Schema#lazy_resolve}
    # @param args [GraphQL::Query::Arguments] Arguments to this field
    # @param ctx [GraphQL::Query::Context] Context for this field
    # @return [Object] The result of calling the registered method on `obj`
    def lazy_resolve(obj, args, ctx)
      @lazy_resolve_proc.call(obj, args, ctx)
    end

    # Assign a new resolve proc to this field. Used for {#lazy_resolve}
    def lazy_resolve=(new_lazy_resolve_proc)
      @lazy_resolve_proc = new_lazy_resolve_proc
    end

    # Prepare a lazy value for this field. It may be `then`-ed and resolved later.
    # @return [GraphQL::Execution::Lazy] A lazy wrapper around `obj` and its registered method name
    def prepare_lazy(obj, args, ctx)
      GraphQL::Execution::Lazy.new {
        lazy_resolve(obj, args, ctx)
      }
    end

    # @return [GraphQL::Query::Arguments] Arguments to use when no args are provided in the query
    def default_arguments
      @default_arguments ||= GraphQL::Query::LiteralInput.defaults_for(self.arguments)
    end

    private

    def build_default_resolver
      GraphQL::Field::Resolve.create_proc(self)
    end

    module DefaultLazyResolve
      def self.call(obj, args, ctx)
        method_name = ctx.schema.lazy_method_name(obj)
        obj.public_send(method_name)
      end
    end
  end
end
