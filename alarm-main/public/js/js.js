console.log("Page load start");

$(function() {
  console.log("Page load finish");

  

  // Check if alarm is ringing
  if ($("#alarm-status").attr("data-triggered") == "true") {
    $(".alarm-ringing").text("ALARM TRIGGERED")
  }
  if ($(".alarm-ringing").attr("data-active") == "true") {
    alarmRingingWhite();
  }
});

// Alarm ringing
var i = 1;
function alarmRingingWhite () {
   setTimeout(function () {
      $(".alarm-ringing").css("color", "white");
      i++;
      if (i < 1000) {
         alarmRingingRed();
      }
   }, 3000)
}
function alarmRingingRed () {
  setTimeout(function () {
    $(".alarm-ringing").css("color", "red");
    i++;
    if (i < 1000) {
        alarmRingingWhite();
    }
  }, 3000)
}
// Password typing
  $(".codebtn").click(function() {
    console.log("Password char typed")
    var char = $(this).attr("data-value");
    var currPwd = $("#disarm-password").val();
    $("#disarm-password").val(currPwd + char);
  });

  $(".btn-clear").click(function() {
    console.log("Clearing password input")
    $("#disarm-password").val("");
  });

  $(".btn-disarm").click(function() {
    var pwd = $("#disarm-password").val();
    if (pwd) {
      $.ajax({
        type: "POST",
        url: "/disarmconfirm?password=" + pwd,
        success: function(response) {
          if (response != "ERROR") {
            console.log("Password accepted");
            $(".password-message").css("color", "green");
            $(".password-message").text("Password accepted").fadeIn(300);
            window.location.href = "/";
          } else {
            console.log("Wrong password");
            $("#disarm-password").val("");
            $(".password-message").text("Wrong password").fadeIn(300);
          }
        },
        error: function(xhr,textStatus,e) {
          console.log("Wrong password");
          $(".password-message").text("Wrong password").fadeIn(300);
        }
      });
    } else {
      console.log("Missing password");
      $(".password-message").text("No input").fadeIn(300);
    }
  });