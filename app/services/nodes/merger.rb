# frozen_string_literal: true

class Nodes::Merger
  def self.call(target_node, source_node)
    new(target_node, source_node).call
  end

  def initialize(target_node, source_node)
    @source_node = source_node
    @target_node = target_node
  end

  def call
    Node.transaction do
      move_descendents
      reset_counter_caches
      update_properties
      copy_attachments

      Node.destroy(source_node.id)
    end
  rescue StandardError => e
    Rails.logger.error 'Node merge error occured, attempting to rectify attachments.'
    Rails.logger.error e.backtrace

    undo_attachments_copy

    source_node
  end

  private

    attr_accessor :target_node, :source_node, :copied_attachments

    DESCENDENT_RELATIONSHIPS = {
      activities: :trackable_id,
      children: :parent_id,
      evidence: :node_id,
      notes: :node_id
    }.freeze

    def move_descendents
      DESCENDENT_RELATIONSHIPS.each do |relation, column|
        source_node.send(relation).update_all(column => target_node.id)
      end
    end

    def reset_counter_caches
      Node.reset_counters target_node.id, :children_count
    end

    def update_properties
      source_node.properties.each do |key, value|
        target_node.set_property key, value
      end

      target_node.save
    end

    def copy_attachments
      self.copied_attachments = []

      source_node.attachments.each do |attachment|
        copied_attachments << attachment.copy_to(target_node)
      end
    end

    def undo_attachments_copy
      return unless copied_attachments&.any?
      copied_attachments.each(&:delete)
    end
end
