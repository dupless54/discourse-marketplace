export default function () {
  this.route("marketplace", { path: "/marketplace" }, function () {
    this.route("new");
    this.route("mine");
    this.route("favorites");
    this.route("offers");
    this.route("transactions");
    this.route("listing", { path: "/listings/:listing_id" }, function () {
      this.route("edit");
    });
  });
}
