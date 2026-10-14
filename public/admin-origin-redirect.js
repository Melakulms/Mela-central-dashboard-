// Retire same-origin administrator logins on GitHub Pages. This script must
// run synchronously in the document head before the Admin app bootstraps.
// Never forward URL search/hash secrets to the separate administrative origin.
if (window.location.origin === 'https://melakulms.github.io' &&
    /^\/Mela-central-dashboard-(?:\/|$)/.test(window.location.pathname)) {
  window.location.replace('https://central-dashboard-gamma.vercel.app/Mela-central-dashboard-/')
}
