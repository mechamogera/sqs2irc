## このスクリプトについて

* sqsのメッセージをircに送る
* daemonとして実行するのでcronに仕込めば落ちても起動してくれる

## 使い方

* awsのsqsのqueueとsnsのtopic(Subscriptionには作成したsqs指定)作成
* conf/sqs2irc.ymlを適切に設定(作成したsqs指定)
* 実行

```
bundle install --path vendor/bundle
bundle exec ruby sqs2irc.rb start # daemonとして実行
```

* 以下のようなJSONフォーマットでsnsにpublishするとircにつぶやく

```
{"channel":"#test","notices":["notice message0","notice message1"],"privmsgs":["priv message0","priv message1"]}
```
