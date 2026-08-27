# frozen_string_literal: true

describe Marketplace::Listing do
  fab!(:category) { Fabricate(:marketplace_category) }
  fab!(:seller) { Fabricate(:user) }

  before { SiteSetting.marketplace_allowed_currencies = "USD|EUR" }

  def build_listing(**overrides)
    Fabricate.build(:marketplace_listing, seller: seller, category: category, **overrides)
  end

  it "is valid with valid attributes" do
    expect(build_listing).to be_valid
  end

  it "requires a title between 3 and 255 characters" do
    expect(build_listing(title: "ab")).not_to be_valid
    expect(build_listing(title: "a" * 256)).not_to be_valid
    expect(build_listing(title: "abc")).to be_valid
  end

  it "requires price_cents to be >= 0" do
    expect(build_listing(price_cents: -1)).not_to be_valid
    expect(build_listing(price_cents: 0)).to be_valid
  end

  it "requires an uppercase 3-letter currency in the allowlist" do
    expect(build_listing(currency: "usd")).not_to be_valid
    expect(build_listing(currency: "XXX")).not_to be_valid
    expect(build_listing(currency: "USD")).to be_valid
  end

  it "rejects a disabled category on create" do
    disabled_category = Fabricate(:marketplace_category, enabled: false)
    expect(build_listing(category: disabled_category)).not_to be_valid
  end

  it "does not re-validate category enablement on unrelated updates once persisted" do
    listing = build_listing
    listing.save!
    listing.category.update!(enabled: false)
    listing.title = "Updated title"
    expect(listing).to be_valid
  end

  it "rejects switching to a disabled category on update" do
    listing = build_listing
    listing.save!
    disabled_category = Fabricate(:marketplace_category, enabled: false)
    listing.category_id = disabled_category.id
    expect(listing).not_to be_valid
  end

  it "allows a status-only change after the listing's category becomes disabled" do
    listing = build_listing
    listing.save!
    listing.category.update!(enabled: false)
    listing.status = Marketplace::Listing.statuses[:archived]
    expect(listing).to be_valid
  end

  describe "images/attachments" do
    it "associates uploads referenced in raw via UploadReference on create" do
      upload = Fabricate(:upload)
      listing = build_listing(raw: "See the photo: #{upload.short_url}")
      listing.save!

      expect(UploadReference.where(target: listing).pluck(:upload_id)).to contain_exactly(upload.id)
    end

    it "does not touch upload references when raw is unchanged" do
      upload = Fabricate(:upload)
      listing = build_listing(raw: "See the photo: #{upload.short_url}")
      listing.save!

      expect { listing.update!(title: "A different title") }.not_to change {
        UploadReference.where(target: listing).count
      }
    end

    it "drops the reference to an upload no longer mentioned after an edit" do
      old_upload = Fabricate(:upload)
      new_upload = Fabricate(:upload)
      listing = build_listing(raw: "See the photo: #{old_upload.short_url}")
      listing.save!

      listing.update!(raw: "See the new photo: #{new_upload.short_url}")

      expect(UploadReference.where(target: listing).pluck(:upload_id)).to contain_exactly(new_upload.id)
    end

    it "has no upload references when raw mentions no uploads" do
      listing = build_listing
      listing.save!

      expect(UploadReference.where(target: listing)).to be_empty
    end
  end
end
