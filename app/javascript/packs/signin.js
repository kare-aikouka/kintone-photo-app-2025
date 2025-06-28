import $ from "jquery";

$(function () {
  if (location.hash) {
    $('#hashbang').val(location.hash);
  }
});
