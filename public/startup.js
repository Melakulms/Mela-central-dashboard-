(function () {
  var status = document.getElementById('startup-status')
  var errorBox = document.getElementById('startup-error')

  window.__melaShowStartupError = function (message) {
    status.style.display = 'flex'
    errorBox.textContent = String(message || 'Unknown startup error')
  }

  window.addEventListener('error', function (event) {
    window.__melaShowStartupError(event.error && event.error.message ? event.error.message : event.message)
  })

  window.addEventListener('unhandledrejection', function (event) {
    var reason = event.reason
    window.__melaShowStartupError(reason && reason.message ? reason.message : reason)
  })
}())
