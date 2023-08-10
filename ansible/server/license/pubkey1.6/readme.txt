
work with $ynop$ys 2019+

synopsys_checksum v0.9:  first release
synopsys_checksum v1.0:  add windows support, and you can use synopsys_checksum -s to get encrypted strings from binary files(such as feature names)
pubkey_verify           v1.2:  add more rules to check patch point
synopsys_checksum v1.1:  use nftw to search dirs, and not follow soft links
pubkey_verify           v1.3:  use nftw to search dirs, and not follow soft links
synopsys_checksum v1.2:  fix a core dump bug
pukey_verify             v1.4:  recompile with big file system support
synopsys_checksum v1.3:  recompile with big file system support
synopsys_checksum v1.4:  imporve string search algorithm
synopsys_checksum v1.5:  fix bug when locate the patch point(linux64). Add synopsys.src. Add fix.bat
synopsys_checksum v1.6:  enhance patch point locate algorithm(windows). 

How to use ?

1. [in linux box]Patch files. Goto syn_vP-2019.03 dir, run pubkey_verify -y 
2. [in linux box]Patch files' checksum. Goto syn_vP-2019.03 dir, run synopsys_checksum -y
3. [in linux box]Repeat 1, 2 with all your $ynopsys , including scl_v2018.06
4. [in windows box]Generate license file(Synopsys.dat) with scl_keygen.exe. 
5. [in windows box]Drap&drop the generated Synopsys.dat to fix.bat. This will add dummy SIGN= to the license file.
6. Copy the license file to you linux box, and start the license daemon.
7. Run


Some Tips about get more feature:
export FLEXLM_DIAGNOSTICS=10
then run your app, and will report missing features

000c29953737

