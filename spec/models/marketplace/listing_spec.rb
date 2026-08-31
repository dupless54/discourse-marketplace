# frozen_string_literal: true

describe Marketplace::Listing do
  fab!(:category, :marketplace_category)
  fab!(:seller, :user)

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

  describe "inventory_mode" do
    it "defaults to single" do
      expect(build_listing.inventory_mode).to eq("single")
    end

    it "requires stock_quantity for finite" do
      expect(build_listing(inventory_mode: :finite, stock_quantity: nil)).not_to be_valid
      expect(build_listing(inventory_mode: :finite, stock_quantity: 0)).not_to be_valid
      expect(build_listing(inventory_mode: :finite, stock_quantity: 1)).to be_valid
    end

    it "rejects a stock_quantity for single or unlimited" do
      expect(build_listing(inventory_mode: :single, stock_quantity: 5)).not_to be_valid
      expect(build_listing(inventory_mode: :unlimited, stock_quantity: 5)).not_to be_valid
    end

    it "rejects stock_reserved + stock_sold exceeding stock_quantity" do
      listing =
        build_listing(inventory_mode: :finite, stock_quantity: 2, stock_reserved: 2, stock_sold: 1)
      expect(listing).not_to be_valid
      expect(listing.errors[:stock_quantity]).to be_present
    end

    it "allows stock_reserved + stock_sold exactly equal to stock_quantity" do
      listing =
        build_listing(inventory_mode: :finite, stock_quantity: 2, stock_reserved: 1, stock_sold: 1)
      expect(listing).to be_valid
    end

    it "prevents changing inventory_mode once the listing has any transaction history" do
      listing = build_listing(inventory_mode: :finite, stock_quantity: 3)
      listing.save!
      Fabricate(:marketplace_transaction, listing: listing)

      listing.inventory_mode = Marketplace::Listing.inventory_modes[:single]
      listing.stock_quantity = nil

      expect(listing).not_to be_valid
      expect(listing.errors[:inventory_mode]).to be_present
    end

    it "allows changing inventory_mode before any transaction exists" do
      listing = build_listing(inventory_mode: :single)
      listing.save!

      listing.inventory_mode = Marketplace::Listing.inventory_modes[:finite]
      listing.stock_quantity = 3

      expect(listing).to be_valid
    end
  end

  describe "#expired?" do
    it "is false when expires_at is nil" do
      expect(build_listing(expires_at: nil).expired?).to eq(false)
    end

    it "is false for a future expires_at" do
      expect(build_listing(expires_at: 1.hour.from_now).expired?).to eq(false)
    end

    it "is true for a past expires_at" do
      expect(build_listing(expires_at: 1.hour.ago).expired?).to eq(true)
    end
  end

  describe "#stock_available" do
    it "is nil for single" do
      expect(build_listing(inventory_mode: :single).stock_available).to be_nil
    end

    it "is nil for unlimited" do
      expect(build_listing(inventory_mode: :unlimited).stock_available).to be_nil
    end

    it "is the remaining count for finite" do
      listing =
        build_listing(inventory_mode: :finite, stock_quantity: 5, stock_reserved: 2, stock_sold: 1)
      expect(listing.stock_available).to eq(2)
    end

    it "never goes below zero" do
      listing =
        build_listing(inventory_mode: :finite, stock_quantity: 2, stock_reserved: 1, stock_sold: 1)
      expect(listing.stock_available).to eq(0)
    end
  end

  describe "#purchasable?" do
    it "is false when not active" do
      listing = build_listing(status: Marketplace::Listing.statuses[:draft])
      expect(listing.purchasable?).to eq(false)
    end

    it "is false when expired" do
      listing =
        build_listing(status: Marketplace::Listing.statuses[:active], expires_at: 1.hour.ago)
      expect(listing.purchasable?).to eq(false)
    end

    it "is true for an active single listing" do
      listing =
        build_listing(status: Marketplace::Listing.statuses[:active], inventory_mode: :single)
      expect(listing.purchasable?).to eq(true)
    end

    it "is true for an active unlimited listing regardless of stock_sold" do
      listing =
        build_listing(
          status: Marketplace::Listing.statuses[:active],
          inventory_mode: :unlimited,
          stock_sold: 500,
        )
      expect(listing.purchasable?).to eq(true)
    end

    it "is true for an active finite listing with remaining stock" do
      listing =
        build_listing(
          status: Marketplace::Listing.statuses[:active],
          inventory_mode: :finite,
          stock_quantity: 3,
          stock_reserved: 1,
          stock_sold: 1,
        )
      expect(listing.purchasable?).to eq(true)
    end

    it "is false for an active finite listing with no remaining stock" do
      listing =
        build_listing(
          status: Marketplace::Listing.statuses[:active],
          inventory_mode: :finite,
          stock_quantity: 2,
          stock_reserved: 1,
          stock_sold: 1,
        )
      expect(listing.purchasable?).to eq(false)
    end
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

      expect(UploadReference.where(target: listing).pluck(:upload_id)).to contain_exactly(
        new_upload.id,
      )
    end

    it "has no upload references when raw mentions no uploads" do
      listing = build_listing
      listing.save!

      expect(UploadReference.where(target: listing)).to be_empty
    end
  end

  describe "#thumbnail_url" do
    it "returns the src of the first non-emoji image in cooked" do
      listing =
        build_listing(
          cooked:
            '<p>Check it out</p><img src="/uploads/default/original/1X/photo.png" width="100" height="80">',
        )

      expect(listing.thumbnail_url).to eq("/uploads/default/original/1X/photo.png")
    end

    it "ignores emoji images and falls through to the next real image" do
      listing =
        build_listing(
          cooked:
            '<p><img src="/images/emoji/twitter/smile.png" class="emoji"> Great deal!</p>' \
              '<img src="/uploads/default/original/1X/photo.png">',
        )

      expect(listing.thumbnail_url).to eq("/uploads/default/original/1X/photo.png")
    end

    it "returns nil for plain text content with no image" do
      listing = build_listing(cooked: "<p>Just a text description, no photo.</p>")

      expect(listing.thumbnail_url).to be_nil
    end

    it "returns nil for a non-image attachment (does not break generic file attachments)" do
      listing =
        build_listing(
          cooked:
            '<p><a class="attachment" href="/uploads/default/original/1X/manual.pdf">manual.pdf</a></p>',
        )

      expect(listing.thumbnail_url).to be_nil
    end
  end

  describe ".cook" do
    it "wraps an embedded image in the lightbox markup PhotoSwipe activates client-side" do
      upload = Fabricate(:upload)
      cooked = Marketplace::Listing.cook("![photo](#{upload.short_url})")
      fragment = Nokogiri::HTML5.fragment(cooked)

      wrapper = fragment.at_css("div.lightbox-wrapper")
      expect(wrapper).to be_present

      link = wrapper.at_css("a.lightbox")
      expect(link).to be_present
      expect(link["href"]).to eq(upload.url)
      expect(link.at_css("img")).to be_present
    end

    it "does not double-wrap an image the markdown already linked" do
      cooked =
        Marketplace::Listing.cook(
          "[![alt](https://example.com/photo.png)](https://example.com/full.png)",
        )
      fragment = Nokogiri::HTML5.fragment(cooked)

      expect(fragment.css("div.lightbox-wrapper")).to be_empty
      expect(fragment.css("a.lightbox")).to be_empty
      # the original hand-authored link survives untouched
      expect(fragment.at_css("a img")).to be_present
    end

    it "does not wrap emoji images" do
      cooked = Marketplace::Listing.cook("Nice deal! :+1:")
      fragment = Nokogiri::HTML5.fragment(cooked)

      expect(fragment.css("div.lightbox-wrapper")).to be_empty
    end

    it "leaves plain text content with no image untouched" do
      cooked = Marketplace::Listing.cook("Just a text description, no photo.")

      expect(cooked).not_to include("lightbox")
    end
  end
end
