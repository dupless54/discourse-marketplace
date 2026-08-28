# frozen_string_literal: true

module Marketplace
  class CategoryFieldDefinition < ActiveRecord::Base
    self.table_name = "marketplace_category_field_definitions"

    FIELD_TYPES = %w[text textarea integer boolean select].freeze
    KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
    CHOICE_VALUE_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
    MAX_FIELDS_PER_CATEGORY = 30
    MAX_SELECT_CHOICES = 50
    MAX_CHOICE_VALUE_LENGTH = 50
    MAX_CHOICE_LABEL_LENGTH = 100

    belongs_to :category, class_name: "Marketplace::Category"
    has_many :listing_field_values,
             class_name: "Marketplace::ListingFieldValue",
             foreign_key: :field_definition_id,
             inverse_of: :field_definition

    validates :key,
              presence: true,
              uniqueness: {
                scope: :category_id,
              },
              length: {
                maximum: 50,
              },
              format: {
                with: KEY_FORMAT,
              }
    validates :label, presence: true, length: { maximum: 100 }
    validates :field_type, inclusion: { in: FIELD_TYPES }
    validates :required, :enabled, inclusion: { in: [true, false] }
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :placeholder, length: { maximum: 150 }, allow_blank: true
    validates :help_text, length: { maximum: 500 }, allow_blank: true
    validate :category_field_limit, on: :create
    validate :key_is_immutable, on: :update
    validate :type_is_immutable_once_used, on: :update
    validate :choices_are_valid
    validate :used_select_choices_are_retained, on: :update
    validate :display_text_contains_no_html

    scope :ordered, -> { order(:position, :id) }
    scope :enabled, -> { where(enabled: true) }

    def public_schema
      {
        key: key,
        label: label,
        type: field_type,
        required: required,
        position: position,
        choices: choices,
        placeholder: placeholder,
        help_text: help_text,
      }
    end

    private

    def category_field_limit
      return if category_id.blank?
      return if self.class.where(category_id: category_id).count < MAX_FIELDS_PER_CATEGORY

      errors.add(:base, I18n.t("marketplace.errors.too_many_category_fields"))
    end

    def key_is_immutable
      return if !will_save_change_to_key?

      errors.add(:key, I18n.t("marketplace.errors.field_key_immutable"))
    end

    def type_is_immutable_once_used
      return if !will_save_change_to_field_type?
      return if listing_field_values.none?

      errors.add(:field_type, I18n.t("marketplace.errors.field_type_immutable"))
    end

    def choices_are_valid
      if field_type != "select"
        errors.add(:choices, :invalid) if choices.present?
        return
      end

      if !choices.is_a?(Array) || choices.empty? || choices.length > MAX_SELECT_CHOICES
        errors.add(:choices, :invalid)
        return
      end

      values = []
      choices.each do |choice|
        if !choice.is_a?(Hash) || choice.keys.map(&:to_s).sort != %w[label value]
          errors.add(:choices, :invalid)
          return
        end

        value = choice["value"] || choice[:value]
        label = choice["label"] || choice[:label]
        if !value.is_a?(String) ||
             !value.match?(CHOICE_VALUE_FORMAT) ||
             value.length > MAX_CHOICE_VALUE_LENGTH ||
             !label.is_a?(String) ||
             label.blank? ||
             label.length > MAX_CHOICE_LABEL_LENGTH
          errors.add(:choices, :invalid)
          return
        end

        values << value
      end

      errors.add(:choices, :taken) if values.uniq.length != values.length
    end

    def used_select_choices_are_retained
      return if field_type != "select" || !will_save_change_to_choices?

      configured_values = choices.filter_map { |choice| choice["value"] || choice[:value] }
      used_values = listing_field_values.distinct.pluck(:value)
      return if (used_values - configured_values).empty?

      errors.add(:choices, I18n.t("marketplace.errors.used_select_choice_removed"))
    end

    def display_text_contains_no_html
      { label: label, placeholder: placeholder, help_text: help_text }.each do |attribute, value|
        next if value.blank?
        next if Nokogiri::HTML5.fragment(value).at_css("*").blank?

        errors.add(attribute, I18n.t("marketplace.errors.html_not_allowed"))
      end

      return if !choices.is_a?(Array)

      choices.each do |choice|
        choice_label = choice.is_a?(Hash) ? (choice["label"] || choice[:label]) : nil
        next if choice_label.blank?
        next if Nokogiri::HTML5.fragment(choice_label).at_css("*").blank?

        errors.add(:choices, I18n.t("marketplace.errors.html_not_allowed"))
        break
      end
    end
  end
end
