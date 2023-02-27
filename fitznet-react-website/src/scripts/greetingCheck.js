window.addEventListener('load', function() {
    this.alert('Hello, World!');
    // check whether the visitor has already seen the greeting message
    if (!localStorage.getItem('greetingShown')) {
      // display the greeting message
      document.getElementById('greeting-message').style.display = 'block';
      // set a cookie or local storage item to remember that the message has been shown
      localStorage.setItem('greetingShown', 'true');
    }
  });