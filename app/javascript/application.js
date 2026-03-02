// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
// In your application.js or similar file
import "bootstrap"
import "chartkick"
import "chart.js/auto"

document.addEventListener("turbo:load", function () {
  if (window.Chartkick) {
    Chartkick.eachChart(function(chart) {
      chart.redraw();
    });
  }
});