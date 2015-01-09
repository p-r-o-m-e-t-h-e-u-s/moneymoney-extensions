-- ---------------------------------------------------------------------------------------------------------------------
--
-- MoneyMoney Web Banking Extension
-- http://moneymoney-app.com/api/webbanking
--
--
-- The MIT License (MIT)
--
-- Copyright (c) 2012-2014 MRH applications GmbH
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- ---------------------------------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------------------------------
--
-- Get portfolio of DWS Investments.
--
-- ATTENTION: This extension requires MoneyMoney version 2.2.3 or higher
--
-- ---------------------------------------------------------------------------------------------------------------------


-- ---------------------------------------------------------------------------------------------------------------------
-- Common MoneyMoney extension informations
-- ---------------------------------------------------------------------------------------------------------------------

WebBanking {
  version = 0.92,
  country = "de",
  url = "https://depot.dws.de/",
  description = string.format(MM.localizeText("Get portfolio of %s"), "DWS Investments")
}

-- ---------------------------------------------------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------------------------------------------------

local function strToAmount(str)
  -- Helper function for converting localized amount strings to Lua numbers.
  return string.gsub(string.gsub(string.gsub(str, " .+", ""), "%.", ""), ",", ".")
end

-- ---------------------------------------------------------------------------------------------------------------------

local function strToAmountWithDefault(str, defaultValue)
  -- Helper function for converting localized amount strings to Lua numbers with a default value.
  local value = strToAmount(str)
  if value == nil or value == "" then
    value = defaultValue
  end
  return value
end

-- ---------------------------------------------------------------------------------------------------------------------

local function strToDate(str)
  -- Helper function for converting localized date strings to timestamps.
  local d, m, y = string.match(str, "(%d%d)%.(%d%d)%.(%d%d%d%d)")
  if d and m and y then
    return os.time { year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }
  end
end

-- ---------------------------------------------------------------------------------------------------------------------

local function printElementWithPrefix(prefix, element)
  -- Helper function  for debugging HTML elements with a prtinable prefix
  if element:children():length() >= 1 then
    element:children():each(function(index, element2)
      local newPrefix = prefix .. "-" .. index
      print(newPrefix .. "=" .. element2:text())
      printElementWithPrefix(newPrefix, element2)
    end)
  end
end

-- ---------------------------------------------------------------------------------------------------------------------

local function printElement(element)
  -- Helper function  for debugging HTML elements
  printElementWithPrefix('0', element)
end


-- ---------------------------------------------------------------------------------------------------------------------
-- The following variables are used to save state.
-- ---------------------------------------------------------------------------------------------------------------------

local connection
local overview_html


-- ---------------------------------------------------------------------------------------------------------------------
--
-- MoneyMoney API Extension
--
-- @see: http://moneymoney-app.com/api/webbanking/
--
-- ---------------------------------------------------------------------------------------------------------------------

function SupportsBank(protocol, bankCode)
  -- Using artificial bankcode to identify the DWS Investments group.
  return protocol == ProtocolWebBanking and bankCode == "99971300"
end

-- ---------------------------------------------------------------------------------------------------------------------

function InitializeSession(protocol, bankCode, username, customer, password)

  print("InitializeSession with " .. protocol .. " connecting " .. url)

  -- Create HTTPS connection object.
  connection = Connection()
  connection.language = "de-de"

  -- Fetch login page.
  local html = HTML(connection:get(url))

  -- Fill in login credentials.
  html:xpath("//*[@id='_ctl0_MainPlaceHolder_mainPanel_loginPanel_txtUserID']"):attr("value", username)
  html:xpath("//*[@id='_ctl0_MainPlaceHolder_mainPanel_loginPanel_passwordBox']"):attr("value", password)

  html:xpath("//*[@id='__EVENTTARGET']"):attr("value", "_ctl0$MainPlaceHolder$mainPanel$loginPanel$btnGo$btnGoLinkButton")

  -- Submit login form.
  overview_html = HTML(connection:request(html:xpath("//*[@id='aspnetForm']"):submit()))

  -- Check for failed login.
  local failure = overview_html:xpath("//*[@id='_ctl0_MainPlaceHolder_mainPanel_loginPanel_lblMessage']")
  if failure:length() > 0 then
    print("Login failed. Reason: " .. failure:text())
    return failure:text()
  end

  print("Session initialization completed successfully.")
  return nil
end

-- ---------------------------------------------------------------------------------------------------------------------

function ListAccounts(knownAccounts)

  -- Supports only one account
  local account = {
    owner = overview_html:xpath("//*[@id='_ctl0_MainPlaceHolder_testShadowPanel_welcomePanel_customerNameLabel']"):text(),
    name = "DWS Depot Online",
    accountNumber = overview_html:xpath("//*[@class='AccountOverviewValueLabel']"):text(),
    portfolio = true,
    currency = "EUR",
    type = AccountTypePortfolio
  }

  return { account }
end

-- ---------------------------------------------------------------------------------------------------------------------

function RefreshAccount(account, since)

  local securities = {}

  -- Traverse list of security and parse field values.
  overview_html:xpath("//*[@id='_ctl0_MainPlaceHolder_testShadowPanel_accountsTab_accountsPage_accountDataList_DataArea_defaultRepeater__ctl0_defaultRepeaterTable']/tbody/tr"):each(function(index, element)

    -- Create a new security object.
    local security = {
      -- Number tradeTimestamp: Notierungszeitpunkt; Die Angabe erfolgt in Form eines POSIX-Zeitstempels.
      tradeTimestamp = strToDate(element:xpath("./td[2]/span[3]"):text()),
      -- String name: Bezeichnung des Wertpapiers
      name = element:xpath("./td[1]/a"):text(),
      -- String isin: ISIN
      isin = element:xpath("./td[1]/span[2]"):text(),
      -- String currency: Währung bei Nominalbetrag oder nil bei Stückzahl
      currency = nil, -- element:xpath("./td[1]/span[3]"):text(),
      -- Number quantity: Nominalbetrag oder Stückzahl
      quantity = strToAmount(element:xpath("./td[2]/span[1]"):text()),
      -- Number amount: Wert der Depotposition in Kontowährung
      amount = strToAmount(element:xpath("./td[3]/span[1]"):text()),
      -- Number price: Aktueller Preis oder Kurs
      price = strToAmount(element:xpath("./td[2]/span[2]"):text()),
      -- Number purchasePrice: Kaufpreis oder Kaufkurs
      purchasePrice = strToAmountWithDefault(element:xpath("./td[4]/span[3]"):text(), 0.0),
      -- String currencyOfPrice: Von der Kontowaehrung abweichende Waehrung des Preises.
      currencyOfPrice = element:xpath("./td[1]/span[3]"):text(),
      -- String currencyOfPurchasePrice: Von der Kontowaehrung abweichende Waehrung des Kaufpreises.
      currencyOfPurchasePrice = element:xpath("./td[1]/span[3]"):text()
    }

    table.insert(securities, security)
  end)

  -- Return no balance and transactions, just securities
  return { balance = nil, transactions = nil, securities = securities }
end

-- ---------------------------------------------------------------------------------------------------------------------

function EndSession()

  -- Fetch logout page.
  overview_html:xpath("//*[@id='__EVENTTARGET']"):attr("value", "_ctl0$topNavigation$Logout.aspx|TopMT|6")

  -- Submit logout form.
  local logout_html = HTML(connection:request(overview_html:xpath("//*[@id='aspnetForm']"):submit()))

  print("Logged out successfully!")
end
