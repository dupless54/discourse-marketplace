export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",

  map() {
    this.route("marketplace-categories", { path: "categories" });
  },
};
