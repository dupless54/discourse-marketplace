# frozen_string_literal: true

describe Marketplace::Category do
  fab!(:category) { Fabricate(:marketplace_category) }

  it "requires a unique slug" do
    dup = Fabricate.build(:marketplace_category, slug: category.slug)

    expect(dup).not_to be_valid
    expect(dup.errors[:slug]).to be_present
  end

  it "requires a name" do
    category = Fabricate.build(:marketplace_category, name: nil)

    expect(category).not_to be_valid
  end

  describe ".browsable" do
    it "excludes disabled categories" do
      disabled = Fabricate(:marketplace_category, enabled: false)

      expect(Marketplace::Category.browsable).to include(category)
      expect(Marketplace::Category.browsable).not_to include(disabled)
    end

    it "orders by position" do
      first = Fabricate(:marketplace_category, position: 1)
      second = Fabricate(:marketplace_category, position: 2)

      expect(Marketplace::Category.browsable.index(first)).to be < Marketplace::Category.browsable.index(second)
    end
  end
end
