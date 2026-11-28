    FileView {
        id: freshLoginPassword
        path: "/run/kuwai-fresh-greeter/password"
        printErrors: false
        property bool submitted: false
        onLoaded: {
            if (submitted || text() === "") return;
            submitted = true;
            root.password = text();
            root.submit();
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: !freshLoginPassword.submitted
        onTriggered: freshLoginPassword.reload()
    }
