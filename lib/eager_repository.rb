require 'memoist'

# Usage:
#
# customers = Customer.preload(Customer.orders.line_items.item)
#
# customers.each do |customer|
#   customer.orders.each do |order|
#     order.line_items.each do |line_item|
#       line_item.item  # yay, no more N+1, only 4 queries executed !
#     end
#   end
# end

class EagerRepository
  extend Memoist
  include Enumerable

  def initialize(root, paths = [])
    @root  = root.all
    @paths = paths
  end

  def each(&block)
    return to_enum unless block_given?
    @root.repository.scope { eager_load_graph }
    @root.each(&block)
    self
  end

  def eager_load_graph
    graph = {}
    @paths.each do |path|
      edges = []
      path.relationships.reduce(@root) do |sources, relationship|
        edges << relationship
        graph[edges.dup] ||= Node.new(sources, relationship).targets
      end
    end
  end

  memoize :eager_load_graph

  class Node
    extend Memoist

    def initialize(sources, relationship)
      @sources      = sources
      @relationship = relationship
      eager_load
    end

    def targets
      @relationship.eager_load(@sources)
    end

  private

    def eager_load
      @sources.each { |source| map_targets(source) }
    end

    def map_targets(source)
      id = primary_key.get(source)
      set_association(
        source,
        target_map.fetch(id) { [] },
        Hash[foreign_key.zip(id)]
      )
    end

    def set_association(*args)
      # DM does not provide a public API to set the association without lazy
      # loading the targets. This uses a private API that is unlikely to change.
      @relationship.send(:eager_load_targets, *args)
    end

    def target_map
      targets.group_by { |target| foreign_key.get(target) }
    end

    def primary_key
      @relationship.source_key
    end

    def foreign_key
      @relationship.target_key
    end

    memoize :targets, :target_map, :primary_key, :foreign_key

  end # class Node

  module Model

    def preload(*paths)
      EagerRepository.new(self, paths)
    end

  end # module Model
end # class EagerRepository

DataMapper::Model.append_extensions(EagerRepository::Model)
