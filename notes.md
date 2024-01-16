check compiler version bug

# attack

- hacker can send a lot of token to someone to dos
  - no fund lost but
  - can't ::buyCurvesToken() if is a new token for him
  - can't ::transferAllCurvesTokens()
  - what is the gas usage limit?--------------------

- Hacker can put malicius contrat for receiving fee that revert when selling the token ⇒dos: if you buy you cant withdraw
  - how to set receiver fail only when withdrawing?

# todo

- what is the gas usage limit?--------------------

# question

- why you can export erc20 ? => what are the benefits?


# answered

- if you alredy have erc20 token and withdraw curves deploy again ? no
- if you withdraw you have some erc20token ? => do you have control of those token? yes
- if you withdraw you have some erc20token ? => can you exchange on some dex? yes, i can't see why not
- if you export erc20 you don't get fees? => balanceOf(token,account) return 0 if token is not internall => exactly you don't get fees is designed this way


# bug/hack

- M1-L1: dos attackt => huge array spam to user to  prevent to buy new tokens
- Curves::buyCurvesToken() => to much eth can be sent => eth stuck in contract

# reported
- H1: anyone with balance can claim fees. if you claim fees with different account you can drain FeeSplitter's funds 
- H2:FeeSplitter::setCurves(Curves curves_) has no access control => funds drain?
- H3: dos in paying fees ? revert on receive  only when selling 
  - owner can stuct fund at any time 
  - subject owner can set a referralDestination at any time=> user fund risk to being stuck, no way to withdraw if dos
    - any user can decide to dos at any point 

# not bug
- get a flash loan to buy more balance to claim more fees?
  - create alice token
  - generate fees from alice token
  - create hacker token
  - get loan
  - buy hacker token in large amount 
  - claim fees 
  - sell token
  - pay loan