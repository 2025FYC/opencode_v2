mkdir -p ~/.local/bin
cp /home/jojo/opencode_v2/packages/opencode/dist/opencode-linux-x64/bin/opencode ~/.local/bin/
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc