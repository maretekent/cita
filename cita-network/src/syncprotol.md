# 同步协议

关键字解释:
* 实现者:指代实现同步协议的结构或者逻辑.
* CITA同步原理: <br>
举个栗子: <br>
A,B,C,D四个节点,假如全局高度是150,A节点在100时离线,现在A节点重启后,需要同步. <br>
需要同步块依次是: 101, 102, 103, 104,...149, 150高度块. <br>
由于共识生成块的各种原因,同步块时需要注意关键点是:同步101时,需要102来推动,而同步102时,需要103来推动,等等依次类推的递归过程. <br>
而在同步最后一个块时,即150,需要一个高度是std::usize::MAX的虚拟块推动,这些都是同步协议里面实现的.具体见代码.Forward::reply_syn_req方法. <br>
比较形象描述: "<-" 符号是"推动,验证"的意思. <br>
即 102 <- 102 <-103 <- 104....149 <- 150 <- std::usize::MAX <br>

## 简要说明
协议的主要是chain的状态进行同步,其它的同步暂时不做考虑,内容有一下:

1. 广播状态
2. 同步请求
3. 处理请求
4. 同步状态策略
5. 分包策略
6. 排序策略
7. 同步状态异步化
8. 丢包\坏包处理
9. 超时处理

## 主要描述实现
在描述实现之前:请带着以下几个前提问题.
1. 来之其它节点的状态以及块是不可信的,可是,实现者又不能不去做同步工作,怎么避免这种矛盾问题?
2. 根据什么条件结束同步?
3. 如果正在同步中chain或者network断开了怎么办?

#### 广播状态
接收自身节点的状态,大于等于之前的状态就要广播,主要是防止攻击.

#### 同步请求
发起同步请求的触发时机.
1. 来自其它节点的状态大于当前节点的状态时,实现者发起同步请求.
2. 来自自身节点的状态小于其它节点的状态时,实现者发起同步请求.

触发结束同步的时机
1. 就是当前的节点的状态与全局状态一致时,结束同步
2. 把所有的高度(缓存)到实现者时,结束同步.

#### 处理请求
实现者接收同步过来的块,进行拆分包,排序,然后再获取新组K的包发送给当前节点的chain.

#### 同步状态策略
同步chain的状态策略:把组好的包K发送给chain后,等待chain的状态(异步实现),如果有组好的包K,再发送给chain,以此循环,来更新chain的状态.

#### 分包/排序策略
向其它节点发起同步请求,按迭代步step发起,即step = 20,并且,每一个包的请求是随机向其它节点的任意一个发起.
由于网络的传输,同步者在得到对应请求的多个应答,先后次序也不一致,因此,我们就需要对接收的块包进行排序.
在同步者保存好并且排好序的高度块,一次按照step数目,依次再在同步到chain模块.

由于chain执行在添加块的时候需要执行交易,所以向其它节点同步过来块的速度大于同步者给chain块的速度.

#### 同步状态异步化
发起同步请求与同步高度的逻辑是异步的.
可以在一边同步高度时,一边发起同步请求与接收处理同步的块.

#### 丢包\坏包处理
如果chain内部校验失败时,直接丢掉整个组包,并广播自己的当前状态,实现者需要记住(当前节点)chain即将要同步的高度,与广播过来的高度是否一致:
如果等于,继续获取下个包给chain.
如果小于,报错,重新发起同步操作.
如果大于,则chain发生丢包,坏包的现象,需要根据当前chain的状态,发起一个step,并覆盖当前的Sync里面的同高度值.

#### 超时处理
发起同步请求时超时怎么办?需要什么来打断?怎么打断?怎么重从新发起?
需要靠下次来一个最新全局状态来打破.即超时机制.
