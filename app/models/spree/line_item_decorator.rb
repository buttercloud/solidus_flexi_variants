module Spree
  LineItem.class_eval do
    has_many :ad_hoc_option_values_line_items, dependent: :destroy
    has_many :ad_hoc_option_values, through: :ad_hoc_option_values_line_items
    has_many :product_customizations, dependent: :destroy
    validate :required_option_types

    def required_option_types
      required = product.ad_hoc_option_types.select(&:is_required?)
      required_ids = required.map(&:id)
      selected = ad_hoc_option_values.map(&:ad_hoc_option_type)
      selected_ids = selected.map(&:id)

      res = required_ids.all? { |item| selected_ids.include?(item) }

      if !res
        err_msg_list = (required - selected).map(&:presentation).join(', ')

        self.errors.add(:base, "Some options are required: #{err_msg_list}")
      end
    end

    def options_text # REFACTOR
      if customized?
        str = Array.new

        ad_hoc_opt_values = ad_hoc_option_values.sort_by(&:position)

        ad_hoc_opt_values_group = ad_hoc_option_values.group_by do |opt_value|
          opt_value.ad_hoc_option_type.presentation
        end

        ad_hoc_opt_values_group.each do |opt_type, opt_values|
          tmp = "#{opt_type}: "
          tmp += opt_values.map(&:presentation_with_price).join(", ")
          str << tmp
        end

        product_customizations.each do |customization|
          price_adjustment = (customization.price == 0) ? "" : " (#{Spree::Money.new(customization.price).to_s})"
          customization_type_text = "#{customization.product_customization_type.presentation}#{price_adjustment}"
          opts_text = customization.customized_product_options.map { |opt| opt.display_text }.join(', ')
          str << customization_type_text + ": #{opts_text}"
        end

        str.join("\n")
      else
        variant.options_text
      end
    end

    def customized?
      product_customizations.present? || ad_hoc_option_values.present?
    end

    def cost_price
      (variant.cost_price || 0) + ad_hoc_option_values.map(&:cost_price).inject(0, :+)
    end

    def cost_money
      Spree::Money.new(cost_price, currency: currency)
    end

    def add_customizations(product_customizations_values)
      self.product_customizations = product_customizations_values
      product_customizations_values.each { |product_customization| product_customization.line_item = self }
      product_customizations_values.map(&:save) # it is now safe to save the customizations we built
      customizations_offset_price = product_customizations_values.map {|product_customization| product_customization.price(variant)}.compact.sum
      return customizations_offset_price
    end

    def add_ad_hoc_option_values(ad_hoc_option_value_ids)
      product_option_values = ad_hoc_option_value_ids.map do |cid|
        Spree::AdHocOptionValue.find(cid) if cid.present?
      end.compact
      self.ad_hoc_option_values = product_option_values
      ad_hoc_options_offset_price = product_option_values.map(&:price_modifier).compact.sum
      return ad_hoc_options_offset_price
    end

  end
end
