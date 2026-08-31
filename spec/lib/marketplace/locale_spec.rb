# frozen_string_literal: true

describe Marketplace do
  def flatten_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      full_key = prefix ? "#{prefix}.#{key}" : key.to_s
      value.is_a?(Hash) ? flatten_keys(value, full_key) : full_key
    end
  end

  def load_locale(path)
    YAML.load_file(Rails.root.join("plugins/discourse-marketplace/config/locales/#{path}"))
  end

  it "has exactly the same client-side keys in en and tr_TR" do
    en = load_locale("client.en.yml")["en"]
    tr = load_locale("client.tr_TR.yml")["tr_TR"]

    expect(flatten_keys(tr).sort).to eq(flatten_keys(en).sort)
  end

  it "has exactly the same server-side keys in en and tr_TR" do
    en = load_locale("server.en.yml")["en"]
    tr = load_locale("server.tr_TR.yml")["tr_TR"]

    expect(flatten_keys(tr).sort).to eq(flatten_keys(en).sort)
  end

  it "provides the admin site-settings category label for the plugin's settings.yml group" do
    en = load_locale("client.en.yml")["en"]
    tr = load_locale("client.tr_TR.yml")["tr_TR"]

    expect(en.dig("admin_js", "admin", "site_settings", "categories", "marketplace")).to be_present
    expect(tr.dig("admin_js", "admin", "site_settings", "categories", "marketplace")).to be_present
  end
end
