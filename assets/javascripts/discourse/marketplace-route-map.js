export default function () {
  this.route("marketplace", { path: "/marketplace" }, function () {
    this.route("new");
    this.route("mine");
    this.route("listing", { path: "/listings/:listing_id" }, function () {
      this.route("edit");
    });
  });
}
