'use strict';

var LoginPage  = require('./pages/login.page.js');

describe('login page:', function () {
  var page;

  beforeEach(function () {
    page = new LoginPage();
  });

  it('have title and login', function () {
    expect(page.getTitle()).toEqual('FrontAccounting 2.4.3 - Login');
    page.login('test', 'test');
    expect(page.getTitle()).toEqual('Main Menu');
  });
});
