from selenium import webdriver
import yaml

conf = yaml.load(open('loginDetails.yml'))
myFbEmail = conf['fb_user']['email']
myFbPassword = conf['fb_user']['password']

driver = webdriver.Chrome()

def login(url,usernameId, username, passwordId, password, submit_buttonId):
   driver.get(url)
   driver.find_element_by_id(usernameId).send_keys(username)
   driver.find_element_by_id(passwordId).send_keys(password)
   driver.find_element_by_id(submit_buttonId).click()
    
