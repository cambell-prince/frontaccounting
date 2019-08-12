// conf.js

exports.config = {
  seleniumAddress: 'http://localhost:4444/wd/hub',
  baseUrl: 'http://fa.local',

  // Spec patterns are relative to the location of the conf file. They may
  // include glob patterns.
  suites: {
    login: 'login/*.spec.js',
    banking: ['banking/bankDeposit.spec.js', 'banking/bankTransfer.spec.js'],
    sales: 'sales/*.spec.js',
    purchases: 'purchases/*.spec.js',
  },

  // suites: {
  //   login: 'login/*.spec.js',
  //   banking: ['banking/bankDeposit.spec.js']
  // },

  // Options to be passed to Jasmine-node.
  jasmineNodeOpts: {
    showColors: true, // Use colors in the command line report.
  },

  capabilities: {
    browserName: 'chrome',
    chromeOptions: {
        binary: 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe'
    },
    shardTestFiles: false,
    maxInstances: 1
  }

}
