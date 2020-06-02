# Sonic on SAS

# TL;DR;

Run the following two lines of code in SAS, and open the link in the log, to stream a html page with an embedded Sonic The Hedgehog game!

```
filename playme url "https://raw.githubusercontent.com/allanbowe/sonic/master/sonic.sas";
%inc playme;

```

# What?  Why?

This project is just a bit of fun and a minimalist demonstration of using the [SASjs](https://sasjs.io) framework to stream web apps from SAS.

# How?

You can run the `sonic.sas` file directly in SAS to create the Web Services, or you can use the `sasjs-cli` tool to auto-deploy (using the Viya APIs or [SAS9API](https://sas9api.io)).   Just update the `sasjsconfig.json` and run `sasjs cbd [target]`.

Please note that the streamed game is actually sourced in an iframe from a third party provider (https://funhtml5games.com/?embed=sonic), and may not work if you have a restricted content-security-policy.

